import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/graphql/hubapp_operation.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../catalog/data/product_mapper.dart';
import '../../catalog/domain/money.dart';
import '../../checkout/domain/checkout.dart';
import '../domain/store_credit.dart';
import 'store_credit_queries.dart';

/// Store credit (Vnecoms Credit) through `MagentoEgypt_HubAppAccount`.
///
/// Every call throws [HubAppMissing] when the server doesn't have the module
/// — the caller then keeps to Build 1 — and a [Failure] for anything else.
class StoreCreditRepository {
  StoreCreditRepository(this._client);

  /// The authenticated client: every operation needs the customer's token.
  final GraphQLClient _client;

  /// Transactions per page on 20d (the server allows 1–50).
  static const int pageSize = 20;

  /// The balance, the spending rule and page [currentPage] of transactions.
  Future<StoreCreditAccount> fetchAccount({
    int pageSize = StoreCreditRepository.pageSize,
    int currentPage = 1,
  }) async {
    final data = await runHubAppOperation(
      _client,
      StoreCreditQueries.account,
      variables: {'pageSize': pageSize, 'currentPage': currentPage},
    );
    return _account(data['hmStoreCredit']);
  }

  /// The balance and the spending rule, without transactions (Account row).
  Future<StoreCreditAccount> fetchBalance() async {
    final data = await runHubAppOperation(_client, StoreCreditQueries.balance);
    return _account(data['hmStoreCredit']);
  }

  /// How credit is bought here (20d "Buy credit"); null while the store sells
  /// none, or when what it answered can't be bought.
  Future<StoreCreditTopUp?> fetchTopUp() async {
    final data = await runHubAppOperation(_client, StoreCreditQueries.topUp);
    final json =
        (data['hmStoreCredit'] as Map<String, dynamic>?)?['top_up']
            as Map<String, dynamic>?;
    return json == null ? null : _topUp(json);
  }

  /// The credit on cart [cartId]; null for a guest cart.
  Future<CartStoreCredit?> fetchCartCredit(String cartId) async {
    final data = await runHubAppOperation(
      _client,
      StoreCreditQueries.cartCredit,
      variables: {'cartId': cartId},
    );
    return _cartUpdate(data['cart']).credit;
  }

  /// Uses [amount] of credit on cart [cartId]. The server checks the
  /// customer's group and the balance, and caps what it uses at the order
  /// total; a refusal comes back as a `server` [Failure] with its (localized)
  /// message.
  Future<StoreCreditCartUpdate> apply(String cartId, double amount) async {
    final data = await runHubAppOperation(
      _client,
      StoreCreditQueries.apply,
      variables: {'cartId': cartId, 'amount': amount},
      mutation: true,
    );
    return _cartUpdate(
      (data['hmApplyStoreCredit'] as Map<String, dynamic>?)?['cart'],
    );
  }

  /// Stops using credit on cart [cartId].
  Future<StoreCreditCartUpdate> remove(String cartId) async {
    final data = await runHubAppOperation(
      _client,
      StoreCreditQueries.remove,
      variables: {'cartId': cartId},
      mutation: true,
    );
    return _cartUpdate(
      (data['hmRemoveStoreCredit'] as Map<String, dynamic>?)?['cart'],
    );
  }

  /// The credit order [orderNumber] was paid with; null when it used none.
  Future<Money?> fetchOrderCredit(String orderNumber) async {
    final data = await runHubAppOperation(
      _client,
      StoreCreditQueries.orderCredit,
      variables: {'number': orderNumber},
    );
    final orders =
        (data['customer'] as Map<String, dynamic>?)?['orders']
            as Map<String, dynamic>?;
    final items = orders?['items'] as List<dynamic>? ?? const [];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      if (item['number'] != orderNumber) continue;
      final credit = moneyFromJson(
        (item['total'] as Map<String, dynamic>?)?['hm_store_credit']
            as Map<String, dynamic>?,
      );
      return credit != null && credit.amount.abs() > 0.0001
          ? Money(amount: credit.amount.abs(), currency: credit.currency)
          : null;
    }
    return null;
  }

  StoreCreditAccount _account(Object? json) {
    if (json is! Map<String, dynamic>) {
      // Non-null in the schema: an answer without it is a broken response.
      throw const Failure(FailureKind.server, detail: 'hmStoreCredit is empty');
    }
    final balance = moneyFromJson(json['balance'] as Map<String, dynamic>?);
    final paging = json['page_info'] as Map<String, dynamic>?;
    return StoreCreditAccount(
      balance: balance ?? const Money(amount: 0, currency: 'AED'),
      canUseAtCheckout: json['can_use_at_checkout'] == true,
      transactions: [
        for (final t
            in (json['transactions'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>())
          if (_transaction(t) case final transaction?) transaction,
      ],
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      currentPage: (paging?['current_page'] as num?)?.toInt() ?? 1,
      totalPages: (paging?['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  StoreCreditTransaction? _transaction(Map<String, dynamic> json) {
    final amount = moneyFromJson(json['amount'] as Map<String, dynamic>?);
    final id = (json['id'] as num?)?.toInt();
    if (amount == null || id == null) return null;
    final type = (json['type'] as String?)?.trim() ?? '';
    final label = (json['type_label'] as String?)?.trim() ?? '';
    final description = (json['description'] as String?)?.trim() ?? '';
    final orderNumber = (json['order_number'] as String?)?.trim() ?? '';
    return StoreCreditTransaction(
      id: id,
      type: type,
      typeLabel: label.isNotEmpty ? label : type,
      amount: amount,
      balanceAfter:
          moneyFromJson(json['balance_after'] as Map<String, dynamic>?) ??
          Money(amount: 0, currency: amount.currency),
      description: description.isEmpty ? null : description,
      createdAt: (json['created_at'] as String?)?.trim() ?? '',
      orderNumber: orderNumber.isEmpty ? null : orderNumber,
    );
  }

  StoreCreditTopUp? _topUp(Map<String, dynamic> json) {
    final presets = <StoreCreditPreset>[
      for (final p
          in (json['presets'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
        if (_preset(p) case final preset?) preset,
    ]..sort((a, b) => a.credit.amount.compareTo(b.credit.amount));
    var min = moneyFromJson(json['min'] as Map<String, dynamic>?);
    var max = moneyFromJson(json['max'] as Map<String, dynamic>?);
    final rate = (json['credit_rate'] as num?)?.toDouble();
    if (min == null ||
        max == null ||
        max.amount < min.amount ||
        min.amount <= 0 ||
        rate == null ||
        rate <= 0) {
      // No usable custom range: presets only.
      min = null;
      max = null;
    }
    if (presets.isEmpty && min == null) return null;
    return StoreCreditTopUp(
      sku: (json['sku'] as String?)?.trim() ?? '',
      min: min,
      max: max,
      creditRate: min == null ? null : rate,
      presets: presets,
    );
  }

  StoreCreditPreset? _preset(Map<String, dynamic> json) {
    final credit = moneyFromJson(json['credit'] as Map<String, dynamic>?);
    final price = moneyFromJson(json['price'] as Map<String, dynamic>?);
    if (credit == null || price == null || credit.amount <= 0) return null;
    return StoreCreditPreset(
      sku: (json['sku'] as String?)?.trim() ?? '',
      credit: credit,
      price: price,
    );
  }

  StoreCreditCartUpdate _cartUpdate(Object? cart) {
    if (cart is! Map<String, dynamic>) return const StoreCreditCartUpdate();
    final credit = cart['hm_store_credit'] as Map<String, dynamic>?;
    final prices = cart['prices'] as Map<String, dynamic>?;
    final methods = cart['available_payment_methods'] as List<dynamic>?;
    return StoreCreditCartUpdate(
      credit: credit == null ? null : _cartCredit(credit),
      grandTotal: moneyFromJson(
        prices?['grand_total'] as Map<String, dynamic>?,
      ),
      paymentMethods: methods
          ?.whereType<Map<String, dynamic>>()
          .map(
            (m) => PaymentMethodOption(
              code: (m['code'] as String?) ?? '',
              title: (m['title'] as String?) ?? '',
              isOnline: m['is_deferred'] == true,
            ),
          )
          .toList(),
    );
  }

  CartStoreCredit _cartCredit(Map<String, dynamic> json) {
    Money money(String key) =>
        moneyFromJson(json[key] as Map<String, dynamic>?) ??
        const Money(amount: 0, currency: 'AED');
    return CartStoreCredit(
      applied: money('applied'),
      balance: money('balance'),
      maxApplicable: money('max_applicable'),
      canUse: json['can_use'] == true,
    );
  }
}

final storeCreditRepositoryProvider = Provider<StoreCreditRepository>(
  (ref) => StoreCreditRepository(ref.watch(graphqlClientProvider)),
);
