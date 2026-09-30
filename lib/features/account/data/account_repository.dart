import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/graphql/resilience_link.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/util/media.dart';
import '../../catalog/data/product_mapper.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/domain/money.dart';
import '../../marketplace/marketplace_features.dart';
import '../domain/customer_address.dart';
import '../domain/order.dart';
import '../domain/saved_card.dart';
import 'account_queries.dart';

class AccountRepository {
  AccountRepository(
    this._client, {
    this._marketplace = const FixedMarketplaceGate(),
  });

  final GraphQLClient _client;

  /// Whether order documents may ask for each line's seller (HubApp); asked
  /// at request time.
  final MarketplaceGate _marketplace;

  Future<OrderPage> fetchOrders({int pageSize = 10, int currentPage = 1}) async {
    final data = await _orderRun(AccountQueries.orders, {
      'pageSize': pageSize,
      'currentPage': currentPage,
    }, mutation: false);
    final orders =
        (data['customer'] as Map<String, dynamic>?)?['orders']
            as Map<String, dynamic>?;
    if (orders == null) return OrderPage.empty;
    final items = (orders['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseOrder)
        .toList();
    final pageInfo = orders['page_info'] as Map<String, dynamic>?;
    return OrderPage(
      items: items,
      totalCount: (orders['total_count'] as int?) ?? items.length,
      currentPage: (pageInfo?['current_page'] as int?) ?? currentPage,
      totalPages: (pageInfo?['total_pages'] as int?) ?? 1,
    );
  }

  /// The signed-in customer's order [number] (the increment id customers see,
  /// e.g. `000000248`), or null when they have no order by that number.
  Future<CustomerOrder?> fetchOrderByNumber(String number) async {
    final data = await _orderRun(AccountQueries.orderByNumber, {
      'number': number,
    }, mutation: false);
    final orders =
        (data['customer'] as Map<String, dynamic>?)?['orders']
            as Map<String, dynamic>?;
    return (orders?['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseOrder)
        .where((order) => order.number == number)
        .firstOrNull;
  }

  /// Guest order lookup by the Magento order token captured at checkout
  /// (`placeOrder.orderV2.token`). Native Magento query — returns the same
  /// `CustomerOrder` type as the customer list, so it parses identically.
  Future<CustomerOrder> fetchGuestOrderByToken(String token) async {
    final data = await _orderRun(AccountQueries.guestOrderByToken, {
      'token': token,
    }, mutation: false);
    return _parseGuestOrder(data['guestOrderByToken']);
  }

  /// Guest order lookup by the details on the confirmation e-mail: order number
  /// + the billing e-mail and last name used at checkout.
  Future<CustomerOrder> fetchGuestOrder({
    required String number,
    required String email,
    required String lastname,
  }) async {
    final data = await _orderRun(AccountQueries.guestOrder, {
      'number': number,
      'email': email,
      'lastname': lastname,
    }, mutation: false);
    return _parseGuestOrder(data['guestOrder']);
  }

  /// A missing/unknown order comes back as a `graphql-no-such-entity` error (so
  /// `_run` already threw); a null payload without an error is treated the same
  /// way rather than surfacing a half-empty order.
  CustomerOrder _parseGuestOrder(Object? payload) {
    if (payload is! Map<String, dynamic>) {
      throw const Failure(FailureKind.unknown);
    }
    return _parseOrder(payload, placedAsGuest: true);
  }

  /// Cancels the signed-in customer's order [orderId] (`CustomerOrder.id`)
  /// for one of the store's cancellation [reason]s and returns the updated
  /// order (null if Magento sent none back).
  ///
  /// Magento reports a refusal — cancellation disabled, something already
  /// shipped, the order complete or on hold — in the payload, not as a
  /// GraphQL error; it becomes a `server` [Failure] carrying the store's own
  /// (localized) message.
  Future<CustomerOrder?> cancelOrder({
    required String orderId,
    required String reason,
  }) async {
    final data = await _orderRun(AccountQueries.cancelOrder, {
      'orderId': orderId,
      'reason': reason,
    }, mutation: true);
    final output = data['cancelOrder'];
    _throwIfCancelRefused(output);
    final order = (output as Map<String, dynamic>)['order'];
    return order is Map<String, dynamic> ? _parseOrder(order) : null;
  }

  /// Asks Magento to cancel a guest order. Nothing is cancelled yet: the
  /// store e-mails the order's billing address a link that confirms it.
  Future<void> requestGuestOrderCancel({
    required String token,
    required String reason,
  }) async {
    final data = await _run(AccountQueries.requestGuestOrderCancel, {
      'token': token,
      'reason': reason,
    }, mutation: true);
    _throwIfCancelRefused(data['requestGuestOrderCancel']);
  }

  void _throwIfCancelRefused(Object? output) {
    if (output is! Map<String, dynamic>) {
      throw const Failure(FailureKind.unknown, detail: 'cancel: no payload');
    }
    final v2 = output['errorV2'];
    final message =
        ((v2 is Map<String, dynamic> ? v2['message'] as String? : null) ??
                (output['error'] as String?) ??
                '')
            .trim();
    if (message.isNotEmpty) throw Failure(FailureKind.server, detail: message);
  }

  /// Whether the signed-in customer is subscribed to the newsletter.
  Future<bool> fetchNewsletterSubscription() async {
    final data = await _run(
      AccountQueries.newsletterStatus,
      const {},
      mutation: false,
    );
    return (data['customer'] as Map<String, dynamic>?)?['is_subscribed'] ==
        true;
  }

  /// Subscribes or unsubscribes the signed-in customer and returns what the
  /// store saved. With "Need to Confirm" on, a new subscription stays `false`
  /// until the customer confirms it from the e-mail Magento sends.
  Future<bool> setNewsletterSubscription(bool subscribed) async {
    final data = await _run(AccountQueries.setNewsletter, {
      'subscribed': subscribed,
    }, mutation: true);
    final saved =
        ((data['updateCustomerV2'] as Map<String, dynamic>?)?['customer']
            as Map<String, dynamic>?)?['is_subscribed'];
    return saved is bool ? saved : subscribed;
  }

  /// Sends the Help centre contact form (core `contactUs`). Throws a
  /// [Failure] unless the store confirms it.
  Future<void> sendContactMessage({
    required String name,
    required String email,
    required String comment,
    String? telephone,
  }) async {
    final phone = telephone?.trim() ?? '';
    final data = await _run(AccountQueries.contactUs, {
      'input': {
        'name': name,
        'email': email,
        'comment': comment,
        if (phone.isNotEmpty) 'telephone': phone,
      },
    }, mutation: true);
    final ok = (data['contactUs'] as Map<String, dynamic>?)?['status'] == true;
    if (!ok) {
      throw const Failure(
        FailureKind.unknown,
        detail: 'contactUs did not confirm the message',
      );
    }
  }

  Future<List<CustomerAddress>> fetchAddresses() async {
    final data = await _run(
      AccountQueries.addresses,
      const {},
      mutation: false,
    );
    final addresses =
        (data['customer'] as Map<String, dynamic>?)?['addresses']
            as List<dynamic>?;
    return (addresses ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseAddress)
        .toList();
  }

  Future<void> createAddress(CustomerAddress address) => _run(
    AccountQueries.createAddress,
    {'input': address.toInput()},
    mutation: true,
  );

  Future<void> updateAddress(int id, CustomerAddress address) => _run(
    AccountQueries.updateAddress,
    {'id': id, 'input': address.toInput()},
    mutation: true,
  );

  Future<void> deleteAddress(int id) =>
      _run(AccountQueries.deleteAddress, {'id': id}, mutation: true);

  /// The cards Magento's vault holds for the customer, whichever gateway
  /// saved them — the app takes no card payments yet, so any card here was
  /// saved on the website. They are listed to be seen and removed, not paid
  /// with, so no gateway is filtered out. Non-card tokens and rows that
  /// don't parse are dropped rather than thrown (see [SavedCard.fromToken]).
  Future<List<SavedCard>> fetchSavedCards() async {
    final data = await _run(
      AccountQueries.savedCards,
      const {},
      mutation: false,
    );
    final items =
        (data['customerPaymentTokens'] as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    return (items ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(SavedCard.fromToken)
        .nonNulls
        .toList();
  }

  Future<void> deleteSavedCard(String publicHash) => _run(
    AccountQueries.deleteSavedCard,
    {'publicHash': publicHash},
    mutation: true,
  );

  Future<void> updateProfile({
    required String firstName,
    required String lastName,
  }) => _run(AccountQueries.updateProfile, {
    'input': {'firstname': firstName, 'lastname': lastName},
  }, mutation: true);

  /// Throws a `server` [Failure] with the store's message when it refuses:
  /// a wrong current password ("Invalid login or password."), a new one it
  /// won't take. A wrong current password is an authentication error on the
  /// mutation's field, so the request is a [CredentialCheck]: it answers the
  /// form and leaves the session alone.
  Future<void> changePassword(String current, String next) => _run(
    AccountQueries.changePassword,
    {'currentPassword': current, 'newPassword': next},
    mutation: true,
    credentialCheck: true,
  );

  /// Replaces the customer's mobile with [mobileNumber] (E.164), proving it
  /// with the WhatsApp [code] that `requestRegistrationOtp` sent to it. Throws
  /// [Failure] (`server`, with the store's message) on a wrong code.
  Future<void> saveMobileNumber(String mobileNumber, String code) async {
    final data = await _run(AccountQueries.saveMobile, {
      'input': {'mobile': mobileNumber, 'otp': code},
    }, mutation: true);
    final saved =
        (data['saveMobileToCustomer'] as Map<String, dynamic>?)?['result'];
    if (saved != true) {
      throw const Failure(
        FailureKind.unknown,
        detail: 'saveMobileToCustomer did not confirm the change',
      );
    }
  }

  /// Discovers the `address_label` select options (id + store-scoped label) so
  /// the "Save as" chips map to option ids without hardcoding. Empty on error.
  Future<List<({String value, String label})>> fetchAddressLabelOptions() async {
    try {
      final data = await _run(
        AccountQueries.addressLabelMetadata,
        const {},
        mutation: false,
      );
      final items =
          (data['customAttributeMetadataV2'] as Map<String, dynamic>?)?['items']
              as List<dynamic>? ??
          const [];
      for (final item in items) {
        if (item is Map<String, dynamic> && item['code'] == 'address_label') {
          return (item['options'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(
                (o) => (
                  value: (o['value'] as String?) ?? '',
                  label: (o['label'] as String?) ?? '',
                ),
              )
              .where((o) => o.value.isNotEmpty && o.label.isNotEmpty)
              .toList();
        }
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  CustomerOrder _parseOrder(
    Map<String, dynamic> json, {
    bool placedAsGuest = false,
  }) {
    final lines = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (l) => OrderLine(
            name: (l['product_name'] as String?) ?? '',
            quantity: (l['quantity_ordered'] as num?)?.toDouble() ?? 1,
            price: moneyFromJson(
              l['product_sale_price'] as Map<String, dynamic>?,
            ),
            imageUrl: httpsMediaUrl(
              (l['product'] as Map<String, dynamic>?)?['image']?['url']
                  as String?,
            ),
            sku: l['product_sku'] as String?,
            urlKey: l['product_url_key'] as String?,
            seller: HmSellerSummary.fromJson(l['hm_seller']),
          ),
        )
        .toList();
    final totals = json['total'] as Map<String, dynamic>?;
    // Magento returns `discounts` as a list (coupon + catalog rules can stack);
    // sum the amounts so the totals reconcile, and keep the first label for the
    // "Discount (<rule>)" line — matching the website order summary.
    final discountList = totals?['discounts'] as List<dynamic>?;
    Money? discount;
    String? discountLabel;
    if (discountList != null && discountList.isNotEmpty) {
      var sum = 0.0;
      var currency = 'AED';
      for (final d in discountList.whereType<Map<String, dynamic>>()) {
        final amt = d['amount'] as Map<String, dynamic>?;
        final v = (amt?['value'] as num?)?.toDouble();
        if (v != null) {
          sum += v;
          currency = (amt?['currency'] as String?) ?? currency;
        }
        final label = (d['label'] as String?)?.trim();
        if (discountLabel == null && label != null && label.isNotEmpty) {
          discountLabel = label;
        }
      }
      if (sum > 0) discount = Money(amount: sum, currency: currency);
    }
    final trackings = <OrderTracking>[];
    final shipments = json['shipments'] as List<dynamic>? ?? const [];
    // Invoices/shipments are what the tracking timeline advances on, so count
    // the shipments themselves — one raised without a tracking number still
    // means the order shipped.
    var shipmentCount = 0;
    for (final shipment in shipments) {
      if (shipment is! Map<String, dynamic>) continue;
      shipmentCount++;
      for (final t in (shipment['tracking'] as List<dynamic>? ?? const [])) {
        if (t is! Map<String, dynamic>) continue;
        final number = (t['number'] as String?) ?? '';
        if (number.isEmpty) continue;
        trackings.add(
          OrderTracking(
            title: (t['title'] as String?) ?? '',
            number: number,
            carrier: (t['carrier'] as String?) ?? '',
          ),
        );
      }
    }
    final comments = (json['comments'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (c) => OrderComment(
            message: (c['message'] as String?) ?? '',
            timestamp: (c['timestamp'] as String?) ?? '',
          ),
        )
        .toList();
    final addr = json['shipping_address'] as Map<String, dynamic>?;
    final billing = json['billing_address'] as Map<String, dynamic>?;
    final payments = json['payment_methods'] as List<dynamic>?;
    String? paymentName;
    if (payments != null && payments.isNotEmpty) {
      final first = payments.first;
      if (first is Map<String, dynamic>) {
        paymentName = first['name'] as String?;
      }
    }
    final token = (json['token'] as String?)?.trim();
    return CustomerOrder(
      number: (json['number'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      date: (json['order_date'] as String?) ?? '',
      id: (json['id'] as String?) ?? '',
      token: (token == null || token.isEmpty) ? null : token,
      availableActions: {
        for (final a in (json['available_actions'] as List<dynamic>?) ??
            const <dynamic>[])
          if (a is String) a,
      },
      placedAsGuest: placedAsGuest,
      total: moneyFromJson(totals?['grand_total'] as Map<String, dynamic>?),
      subtotal: moneyFromJson(totals?['subtotal'] as Map<String, dynamic>?),
      shippingAmount: moneyFromJson(
        totals?['total_shipping'] as Map<String, dynamic>?,
      ),
      discount: discount,
      discountLabel: discountLabel,
      shippingMethod: json['shipping_method'] as String?,
      carrier: json['carrier'] as String?,
      shippingName: _recipientName(addr),
      shippingAddress: _formatAddress(addr),
      shippingPhone: _phone(addr),
      shippingCountryCode: addr?['country_code'] as String?,
      paymentMethodName: paymentName,
      billingName: _recipientName(billing),
      billingAddress: _formatAddress(billing),
      billingPhone: _phone(billing),
      billingCountryCode: billing?['country_code'] as String?,
      lines: lines,
      trackings: trackings,
      comments: comments,
      invoiceCount: (json['invoices'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .length,
      shipmentCount: shipmentCount,
    );
  }

  String? _phone(Map<String, dynamic>? a) {
    final t = (a?['telephone'] as String?)?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  String? _recipientName(Map<String, dynamic>? a) {
    if (a == null) return null;
    final name = [a['firstname'], a['lastname']]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    return name.isEmpty ? null : name;
  }

  String? _formatAddress(Map<String, dynamic>? a) {
    if (a == null) return null;
    final street = (a['street'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    final city = (a['city'] as String?)?.trim() ?? '';
    final region = (a['region'] as String?)?.trim() ?? '';
    // The app derives Magento's required `city` from the emirate, so `city` is a
    // duplicate of the emirate — often in a different language than `region`
    // (e.g. "Dubai" vs "دبي"), which a plain string compare wouldn't catch. Show
    // the emirate once via `region` (falling back to `city` only when region is
    // absent); the country is a separate line. Matches the website
    // (street / emirate / country) — QA 86d3mdefm #3.
    final emirate = region.isNotEmpty ? region : city;
    final parts = <String>[
      if (street.isNotEmpty) street,
      if (emirate.isNotEmpty) emirate,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  CustomerAddress _parseAddress(Map<String, dynamic> json) {
    final streetLines = (json['street'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final region = json['region'] as Map<String, dynamic>?;
    // A free-text region (a store without regions for the country) comes back
    // with region_id 0 — not an id to preselect or send back.
    final regionId = (region?['region_id'] as num?)?.toInt();
    final label = _addressLabel(json['custom_attributesV2']);
    return CustomerAddress(
      id: (json['id'] as num?)?.toInt(),
      firstName: (json['firstname'] as String?) ?? '',
      lastName: (json['lastname'] as String?) ?? '',
      telephone: (json['telephone'] as String?) ?? '',
      street: streetLines.isNotEmpty ? streetLines.first : '',
      apartment: streetLines.length > 1 ? streetLines.sublist(1).join(', ') : '',
      city: (json['city'] as String?) ?? '',
      postcode: (json['postcode'] as String?) ?? '',
      region: (region?['region'] as String?) ?? '',
      regionId: (regionId != null && regionId > 0) ? regionId : null,
      countryCode: (json['country_code'] as String?) ?? 'AE',
      defaultShipping: (json['default_shipping'] as bool?) ?? false,
      defaultBilling: (json['default_billing'] as bool?) ?? false,
      labelOptionId: label?.value,
      labelText: label?.label,
    );
  }

  /// Extracts the selected `address_label` option ({value, label}) from an
  /// address's `custom_attributesV2`, or null when unset.
  ({String value, String label})? _addressLabel(dynamic attrs) {
    if (attrs is! List) return null;
    for (final a in attrs) {
      if (a is Map<String, dynamic> && a['code'] == 'address_label') {
        final selected = a['selected_options'] as List<dynamic>?;
        if (selected != null && selected.isNotEmpty) {
          final opt = selected.first;
          if (opt is Map<String, dynamic>) {
            final value = opt['value'] as String?;
            if (value != null && value.isNotEmpty) {
              return (value: value, label: (opt['label'] as String?) ?? '');
            }
          }
        }
      }
    }
    return null;
  }

  /// Runs an order [document], asking for each line's seller while HubApp
  /// serves `hm_seller`. A server that turns the seller selection down
  /// ("Cannot query field") ran nothing — validation comes first — so the
  /// plain [document] goes out instead, and the gate stops asking.
  Future<Map<String, dynamic>> _orderRun(
    String document,
    Map<String, dynamic> variables, {
    required bool mutation,
  }) async {
    if (!_marketplace.features.sellers) {
      return _run(document, variables, mutation: mutation);
    }
    try {
      return await _run(
        AccountQueries.withSellers(document),
        variables,
        mutation: mutation,
        throwMissing: true,
      );
    } on HubAppMissing {
      _marketplace.sellersMissing();
      return _run(document, variables, mutation: mutation);
    }
  }

  /// [throwMissing]: a "Cannot query field" answer throws [HubAppMissing]
  /// rather than a [Failure]. [credentialCheck]: the request checks a
  /// credential the customer typed ([CredentialCheck]); a field's refusal of
  /// it becomes a `server` [Failure] with the store's message.
  Future<Map<String, dynamic>> _run(
    String document,
    Map<String, dynamic> variables, {
    required bool mutation,
    bool throwMissing = false,
    bool credentialCheck = false,
  }) async {
    final requestContext = credentialCheck
        ? const Context().withEntry(const CredentialCheck())
        : const Context();
    try {
      final result = mutation
          ? await _client.mutate(
              MutationOptions(
                document: gql(document),
                variables: variables,
                fetchPolicy: FetchPolicy.networkOnly,
                context: requestContext,
              ),
            )
          : await _client.query(
              QueryOptions(
                document: gql(document),
                variables: variables,
                fetchPolicy: FetchPolicy.networkOnly,
                context: requestContext,
              ),
            );
      if (result.hasException) {
        final exception = result.exception!;
        if (throwMissing && isHubAppMissing(exception)) {
          throw HubAppMissing(
            exception.graphqlErrors.firstOrNull?.message ?? 'hm_seller',
          );
        }
        if (credentialCheck) {
          final refusal = credentialRefusalMessage(exception);
          if (refusal != null) {
            throw Failure(FailureKind.server, detail: refusal);
          }
        }
        throw mapOperationException(exception);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } on HubAppMissing {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(
    ref.watch(graphqlClientProvider),
    marketplace: ref.watch(marketplaceGateProvider),
  ),
);

/// Paginated orders list state for the signed-in customer.
class OrdersState {
  const OrdersState({
    this.orders = const <CustomerOrder>[],
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<CustomerOrder> orders;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  OrdersState copyWith({
    List<CustomerOrder>? orders,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => OrdersState(
    orders: orders ?? this.orders,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );

  static const Object _keep = Object();
}

/// Owns the customer's orders list with append-on-scroll pagination.
class OrdersController extends AutoDisposeNotifier<OrdersState> {
  static const int _pageSize = 10;

  @override
  OrdersState build() {
    // Re-fetch against the new store view when the language/store switches (the
    // GraphQL cache is reset on switch); otherwise the list keeps the previous
    // store view's data or goes empty. Mirrors CartController's store listener.
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next) Future.microtask(_loadFirst);
      },
    );
    Future.microtask(_loadFirst);
    return const OrdersState();
  }

  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  Future<void> _loadFirst() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.fetchOrders(pageSize: _pageSize, currentPage: 1);
      state = state.copyWith(
        orders: page.items,
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.fetchOrders(
        pageSize: _pageSize,
        currentPage: state.currentPage + 1,
      );
      state = state.copyWith(
        orders: [...state.orders, ...page.items],
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _loadFirst();
}

final ordersControllerProvider =
    AutoDisposeNotifierProvider<OrdersController, OrdersState>(
      OrdersController.new,
    );

/// Saved addresses for the signed-in customer.
final addressesProvider = FutureProvider.autoDispose<List<CustomerAddress>>((
  ref,
) {
  return ref.watch(accountRepositoryProvider).fetchAddresses();
});

/// The signed-in customer's saved cards.
///
/// Error-safe by design: `customerPaymentTokens` 403s for a guest and errors
/// outright until the gateway is vault-aware, and neither is a reason to break
/// the screen. An empty list simply hides Account's Payment Methods row —
/// degrade, never fabricate.
final savedCardsProvider = FutureProvider.autoDispose<List<SavedCard>>((
  ref,
) async {
  if (!ref.watch(authControllerProvider).isAuthenticated) {
    return const <SavedCard>[];
  }
  try {
    return await ref.watch(accountRepositoryProvider).fetchSavedCards();
  } catch (_) {
    return const <SavedCard>[];
  }
});

/// The `address_label` select options (Home/Office/Other → option ids),
/// store-scoped so the AR store returns AR labels. Drives the Save-as chips.
final addressLabelOptionsProvider =
    FutureProvider.autoDispose<List<({String value, String label})>>((ref) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return ref.watch(accountRepositoryProvider).fetchAddressLabelOptions();
    });

/// Real order count for the drawer/account quick-stats (cheap pageSize:1 query).
/// Isolated + error-safe so it never blocks the drawer; 0 on failure.
final customerOrderCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    final page = await ref
        .watch(accountRepositoryProvider)
        .fetchOrders(pageSize: 1);
    return page.totalCount;
  } catch (_) {
    return 0;
  }
});
