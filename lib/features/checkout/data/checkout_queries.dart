/// Hand-written Magento 2.4.8 checkout operations.
abstract final class CheckoutQueries {
  static const String setGuestEmail = r'''
mutation SetGuestEmail($cartId: String!, $email: String!) {
  setGuestEmailOnCart(input: { cart_id: $cartId, email: $email }) {
    cart { email }
  }
}
''';

  // --- Guest-checkout WhatsApp OTP (Vnecoms SMS) -----------------------------
  // Phone-bound, not cart-bound: the code goes to the delivery phone the guest
  // just submitted. Refusals are `success: false` + `msg` (see VnecomsOtp).
  // Only used when BackendCapabilities.guestCheckoutOtp is on — it is off,
  // matching the website, and GraphQL `placeOrder` doesn't check it.
  static const String sendCheckoutOtp = r'''
mutation CheckoutSendOtp($input: CustomerSendOtp!) {
  customerCheckoutSendOtp(input: $input) { success msg }
}
''';

  static const String verifyCheckoutOtp = r'''
mutation CheckoutVerifyOtp($input: CustomerrVerifyOtp!) {
  customerCheckoutVerifyOtp(input: $input) { success msg }
}
''';

  /// Takes a whole `ShippingAddressInput` rather than a bare `CartAddressInput`,
  /// so the caller can send EITHER `{ address: {...} }` for a newly typed
  /// address OR `{ customer_address_id: N }` for one already in the customer's
  /// address book.
  ///
  /// That distinction matters: Magento's SetShippingAddressesOnCart forces
  /// `save_in_address_book = true` whenever an `address` is supplied without
  /// `customer_address_id` and without the flag, so re-sending a saved address
  /// as a literal wrote a duplicate address-book row on every checkout.
  static const String setShippingAddress = r'''
mutation SetShippingAddress($cartId: String!, $shippingAddress: ShippingAddressInput!) {
  setShippingAddressesOnCart(
    input: { cart_id: $cartId, shipping_addresses: [$shippingAddress] }
  ) {
    cart {
      shipping_addresses {
        available_shipping_methods {
          carrier_code
          method_code
          carrier_title
          method_title
          available
          error_message
          amount { value currency }
        }
      }
    }
  }
}
''';

  static const String setShippingMethod = r'''
mutation SetShippingMethod(
  $cartId: String!
  $carrier: String!
  $method: String!
) {
  setShippingMethodsOnCart(
    input: {
      cart_id: $cartId
      shipping_methods: [{ carrier_code: $carrier, method_code: $method }]
    }
  ) {
    cart {
      available_payment_methods { code title }
      prices {
        grand_total { value currency }
        subtotal_including_tax { value currency }
      }
    }
  }
}
''';

  /// `is_deferred` is Magento's "online integration" flag (`!isOffline()`);
  /// checkout offers only the offline methods — see `payableInApp`.
  static const String setBillingSameAsShipping = r'''
mutation SetBilling($cartId: String!) {
  setBillingAddressOnCart(
    input: {
      cart_id: $cartId
      billing_address: { same_as_shipping: true }
    }
  ) {
    cart {
      available_payment_methods { code title is_deferred }
    }
  }
}
''';

  static const String setPaymentMethod = r'''
mutation SetPayment($cartId: String!, $code: String!) {
  setPaymentMethodOnCart(
    input: { cart_id: $cartId, payment_method: { code: $code } }
  ) {
    cart { selected_payment_method { code title } }
  }
}
''';

  static const String placeOrder = r'''
mutation PlaceOrder($cartId: String!) {
  placeOrder(input: { cart_id: $cartId }) {
    order { order_number }
    orderV2 { number token }
  }
}
''';
}
