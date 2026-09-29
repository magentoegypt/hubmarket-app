import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../auth/data/vnecoms_otp.dart';
import '../../catalog/data/product_mapper.dart';
import '../../catalog/domain/money.dart';
import '../domain/checkout.dart';
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

  /// Sets billing = shipping and returns the available payment methods — all
  /// of them; checkout decides which it can take (`payableInApp`).
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
            isOnline: m['is_deferred'] == true,
          ),
        )
        .toList();
  }

  /// Sets the cart's payment method.
  Future<void> setPaymentMethod(String cartId, String code) => _mutate(
    CheckoutQueries.setPaymentMethod,
    {'cartId': cartId, 'code': code},
  );

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
