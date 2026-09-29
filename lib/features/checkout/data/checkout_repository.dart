import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/diagnostics/payment_trace.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../auth/data/vnecoms_otp.dart';
import '../../catalog/data/product_mapper.dart';
import '../../catalog/domain/money.dart';
import '../domain/checkout.dart';
import '../domain/payment_session.dart';
import '../domain/tabby_config.dart';
import 'checkout_queries.dart';

class CheckoutRepository {
  CheckoutRepository(this._client);

  final GraphQLClient _client;

  Future<void> setGuestEmail(String cartId, String email) => _mutate(
    CheckoutQueries.setGuestEmail,
    {'cartId': cartId, 'email': email},
  );

  /// Sets the shipping address and returns the available shipping methods.
  ///
  /// [shippingAddress] is a Magento `ShippingAddressInput`: either
  /// `{'address': {...}}` for a newly entered address, or
  /// `{'customer_address_id': id}` to reuse one from the address book. Passing
  /// a saved address as a literal makes Magento save a *copy* of it — see the
  /// note on [CheckoutQueries.setShippingAddress].
  Future<List<ShippingMethodOption>> setShippingAddress(
    String cartId,
    Map<String, dynamic> shippingAddress,
  ) async {
    final data = await _mutate(CheckoutQueries.setShippingAddress, {
      'cartId': cartId,
      'shippingAddress': shippingAddress,
    });
    final addresses =
        ((data['setShippingAddressesOnCart'] as Map<String, dynamic>?)?['cart']
                as Map<String, dynamic>?)?['shipping_addresses']
            as List<dynamic>?;
    final methods = (addresses != null && addresses.isNotEmpty)
        ? (addresses.first
                  as Map<String, dynamic>)['available_shipping_methods']
              as List<dynamic>?
        : null;
    return (methods ?? const [])
        .whereType<Map<String, dynamic>>()
        // Drop carriers Magento flags as unavailable for this address (these
        // come back with available=false and often a null method_code); keep
        // entries where the flag is absent so an older schema still works.
        .where((m) => m['available'] != false)
        .map(_parseShipping)
        .toList();
  }

  /// Selects a shipping method; returns the updated grand total.
  Future<Money?> setShippingMethod(
    String cartId,
    String carrier,
    String method,
  ) async {
    final data = await _mutate(CheckoutQueries.setShippingMethod, {
      'cartId': cartId,
      'carrier': carrier,
      'method': method,
    });
    final prices =
        ((data['setShippingMethodsOnCart'] as Map<String, dynamic>?)?['cart']
                as Map<String, dynamic>?)?['prices']
            as Map<String, dynamic>?;
    return moneyFromJson(prices?['grand_total'] as Map<String, dynamic>?);
  }

  /// Sets billing = shipping and returns the available payment methods.
  Future<List<PaymentMethodOption>> setBillingSameAsShipping(
    String cartId,
  ) async {
    final data = await _mutate(CheckoutQueries.setBillingSameAsShipping, {
      'cartId': cartId,
    });
    final methods =
        ((data['setBillingAddressOnCart'] as Map<String, dynamic>?)?['cart']
                as Map<String, dynamic>?)?['available_payment_methods']
            as List<dynamic>?;
    return (methods ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => PaymentMethodOption(
            code: (m['code'] as String?) ?? '',
            title: (m['title'] as String?) ?? '',
          ),
        )
        .toList();
  }

  /// Sets the cart's payment method, optionally with the saved-card extras.
  ///
  /// Returns whether the *extras* were accepted; the method itself is set either
  /// way (or throws). [publicHash] pays with a stored card; [saveCard] asks the
  /// gateway to tokenise the card about to be entered.
  ///
  /// Those two sub-inputs are backend additions (§④). A store that hasn't
  /// shipped them rejects the value, so the save opt-in **retries bare** — not
  /// saving a card must never cost the shopper their order. A saved-card
  /// selection deliberately does not fall back: dropping the hash would place
  /// the order against an unspecified token.
  Future<bool> setPaymentMethod(
    String cartId,
    String code, {
    String? publicHash,
    bool saveCard = false,
  }) async {
    final extras = <String, dynamic>{
      if (publicHash != null) 'ngeniusonline_vault': {'public_hash': publicHash},
      if (publicHash == null && saveCard)
        'ngeniusonline': {'is_active_payment_token_enabler': true},
    };
    Future<void> send(Map<String, dynamic> method) => _mutate(
      CheckoutQueries.setPaymentMethod,
      {'cartId': cartId, 'method': method},
    );

    if (extras.isEmpty) {
      await send({'code': code});
      return true;
    }
    try {
      await send({'code': code, ...extras});
      return true;
    } on Failure catch (failure) {
      if (publicHash != null) rethrow;
      PaymentTrace.record(
        'vault: save-card opt-in refused (${failure.kind.name}: '
        '${failure.detail ?? "no detail"}) — retrying without it',
      );
      await send({'code': code});
      return false;
    }
  }

  /// Sends a guest-checkout code to [mobile] (E.164) —
  /// `customerCheckoutSendOtp`. Throws [Failure] (`server`, with the store's
  /// message) when the send is refused.
  Future<void> requestGuestCheckoutOtp(
    String mobile, {
    bool resend = false,
  }) async {
    final data = await _mutate(
      CheckoutQueries.sendCheckoutOtp,
      VnecomsOtp.sendVariables(mobile, resend: resend),
    );
    VnecomsOtp.requireSuccess(data['customerCheckoutSendOtp']);
  }

  /// Checks the guest-checkout [code] for [mobile] —
  /// `customerCheckoutVerifyOtp`. Throws [Failure] on a wrong / expired code.
  Future<void> verifyGuestCheckoutOtp(String mobile, String code) async {
    final data = await _mutate(
      CheckoutQueries.verifyCheckoutOtp,
      VnecomsOtp.verifyVariables(mobile, code),
    );
    VnecomsOtp.requireSuccess(data['customerCheckoutVerifyOtp']);
  }

  Future<PlaceOrderResult> placeOrder(String cartId) async {
    final data = await _mutate(CheckoutQueries.placeOrder, {'cartId': cartId});
    final placed = data['placeOrder'] as Map<String, dynamic>?;
    final order = placed?['order'] as Map<String, dynamic>?;
    final orderV2 = placed?['orderV2'] as Map<String, dynamic>?;
    final number =
        (order?['order_number'] as String?) ?? (orderV2?['number'] as String?);
    // A response without an order number is not a success — surface it as a
    // failure rather than routing the user to a blank-reference success screen.
    if (number == null || number.isEmpty) {
      throw const Failure(FailureKind.unknown);
    }
    final token = orderV2?['token'] as String?;
    return PlaceOrderResult(
      orderNumber: number,
      orderToken: (token != null && token.isNotEmpty) ? token : null,
    );
  }

  // --- Gateway payment sessions / Tabby config -------------------------------
  // The seams the gateway flows (N-Genius card + wallets, Tabby, Tamara) and
  // the "Pay in 4" promo are written against. Hub Market has no resolver behind
  // any of them, so they report "none" without a request; checkout never gets
  // this far on this store, because BackendCapabilities.gatewayPaymentSessions
  // keeps gateway methods out of the list. Restore the operations (contract:
  // docs/backend/payment-contract.md) together with the flag.

  /// The gateway session for a placed order — always null on this backend,
  /// which the callers already treat as "awaiting payment".
  Future<PaymentSession?> fetchPaymentSession(
    String orderNumber, {
    String? email,
    String? lastname,
    String? token,
  }) async {
    PaymentTrace.record(
      'session: none for $orderNumber — this backend has no paymentSession',
    );
    return null;
  }

  /// Switches a placed order to another method and returns its session —
  /// always null here, which keeps the retry screen on "session unavailable".
  Future<PaymentSession?> setOrderPaymentMethod(
    String orderNumber,
    String methodCode, {
    String? email,
    String? lastname,
    String? token,
    String? publicHash,
  }) async {
    PaymentTrace.record(
      'switch: $orderNumber → $methodCode — this backend has no '
      'setOrderPaymentMethod',
    );
    return null;
  }

  /// Tabby products + promo thresholds — always null here (promo hidden).
  Future<TabbyConfig?> fetchTabbyConfig() async => null;

  ShippingMethodOption _parseShipping(Map<String, dynamic> json) =>
      ShippingMethodOption(
        carrierCode: (json['carrier_code'] as String?) ?? '',
        methodCode: (json['method_code'] as String?) ?? '',
        title: [
          json['carrier_title'],
          json['method_title'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        amount: moneyFromJson(json['amount'] as Map<String, dynamic>?),
      );

  Future<Map<String, dynamic>> _mutate(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final checkoutRepositoryProvider = Provider<CheckoutRepository>(
  (ref) => CheckoutRepository(ref.watch(graphqlClientProvider)),
);
