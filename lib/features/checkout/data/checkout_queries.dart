/// Hand-written Magento 2.4.8 checkout operations.
abstract final class CheckoutQueries {
  static const String setGuestEmail = r'''
mutation SetGuestEmail($cartId: String!, $email: String!) {
  setGuestEmailOnCart(input: { cart_id: $cartId, email: $email }) {
    cart { email }
  }
}
''';

  // --- Guest-checkout WhatsApp OTP (MagentoEgypt_OtpVerification) ------------
  // Cart-bound: reads the cart's shipping (fallback billing) `telephone`, so the
  // address (with a full +971… phone) must be set first. `verify` binds the
  // challenge to the quote; the server then lets `placeOrder` through
  // (INTEGRATION.md §7d/§9). On failure both return a GraphQL error with a
  // localized message.
  static const String requestGuestCheckoutOtp = r'''
mutation RequestGuestCheckoutOtp($cartId: String!) {
  requestGuestCheckoutOtp(cartId: $cartId) { success message }
}
''';

  static const String verifyGuestCheckoutOtp = r'''
mutation VerifyGuestCheckoutOtp($cartId: String!, $code: String!) {
  verifyGuestCheckoutOtp(cartId: $cartId, code: $code) { success message }
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

  static const String setBillingSameAsShipping = r'''
mutation SetBilling($cartId: String!) {
  setBillingAddressOnCart(
    input: {
      cart_id: $cartId
      billing_address: { same_as_shipping: true }
    }
  ) {
    cart {
      available_payment_methods { code title }
    }
  }
}
''';

  /// Takes the whole `PaymentMethodInput` as a variable rather than inlining
  /// `{ code: $code }`, so the saved-card extras can ride along without a second
  /// operation: `ngeniusonline_vault: { public_hash }` to pay with a stored
  /// card, `ngeniusonline: { is_active_payment_token_enabler: true }` to save
  /// the one being entered (docs/backend/payment-contract.md §④). Both sub-inputs
  /// are backend additions; `CheckoutRepository.setPaymentMethod` retries
  /// without the save flag if the deployed schema doesn't know it yet.
  static const String setPaymentMethod = r'''
mutation SetPayment($cartId: String!, $method: PaymentMethodInput!) {
  setPaymentMethodOnCart(
    input: { cart_id: $cartId, payment_method: $method }
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

  /// `MagentoEgypt_PaymentGraphQl` resolver — create/return the gateway session
  /// for an already-placed order (docs/backend/payment-contract.md). One resolver
  /// serves both gateways. Until deployed this errors and the repository degrades
  /// to null (checkout shows "awaiting payment").
  static const String paymentSession = r'''
query PaymentSession(
  $orderNumber: String!
  $email: String
  $lastname: String
  $token: String
) {
  paymentSession(
    order_number: $orderNumber
    email: $email
    lastname: $lastname
    token: $token
  ) {
    order_number
    method_code
    gateway
    status
    payment_id
    web_url
    publishable_key
    additional_data { key value }
  }
}
''';

  /// Switches the payment method on an already-placed order and returns a fresh
  /// session, so a guest/customer can retry payment with a different method
  /// without rebuilding the (consumed) cart. Same guest auth as `paymentSession`.
  /// docs/backend/payment-contract.md §①.
  static const String setOrderPaymentMethod = r'''
mutation SetOrderPaymentMethod(
  $orderNumber: String!
  $methodCode: String!
  $email: String
  $lastname: String
  $token: String
) {
  setOrderPaymentMethod(
    input: {
      order_number: $orderNumber
      payment_method: $methodCode
      email: $email
      lastname: $lastname
      token: $token
    }
  ) {
    order_number
    method_code
    gateway
    status
    payment_id
    web_url
    publishable_key
    additional_data { key value }
  }
}
''';

  /// Same switch, but onto a **saved card**: adds `public_hash` to the input.
  ///
  /// Deliberately a second document rather than an optional variable on the one
  /// above. `SetOrderPaymentMethodInput` has no `public_hash` until the backend
  /// ships §④, and an unknown *field* fails document validation even when the
  /// variable is null — which would break the retry screen that works today.
  /// This document is only ever sent when a saved card was actually picked.
  static const String setOrderPaymentMethodWithCard = r'''
mutation SetOrderPaymentMethodWithCard(
  $orderNumber: String!
  $methodCode: String!
  $publicHash: String!
  $email: String
  $lastname: String
  $token: String
) {
  setOrderPaymentMethod(
    input: {
      order_number: $orderNumber
      payment_method: $methodCode
      public_hash: $publicHash
      email: $email
      lastname: $lastname
      token: $token
    }
  ) {
    order_number
    method_code
    gateway
    status
    payment_id
    web_url
    publishable_key
    additional_data { key value }
  }
}
''';

  /// Tabby eligibility + promo metadata (`tabbyConfig`), read from Magento config
  /// (enable flags + thresholds — never hardcoded). Eligibility/promo only;
  /// checkout availability still comes from cart available_payment_methods. Until
  /// deployed this errors and the repository degrades to null (promo hidden).
  static const String tabbyConfig = r'''
query TabbyConfig {
  tabbyConfig {
    enabled
    publishable_key
    merchant_code
    currency
    products {
      type
      method_code
      enabled
      min_amount
      max_amount
      promo_enabled
    }
  }
}
''';
}
