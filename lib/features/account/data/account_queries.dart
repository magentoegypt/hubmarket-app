/// Hand-written Magento 2.4.8 customer account operations (orders, addresses,
/// profile).
abstract final class AccountQueries {
  /// The full `CustomerOrder` selection, shared by the customer order list and
  /// the two guest lookups (`guestOrder` / `guestOrderByToken`) — all three
  /// return the same `CustomerOrder` type, so they parse through `_parseOrder`.
  ///
  /// A real fragment rather than a string spliced into the middle of each
  /// query: `tool/validate_ops.py` can only check complete documents, and the
  /// spliced version hid a field the backend does not have.
  static const String _orderFields = r'''
fragment OrderFields on CustomerOrder {
  number
  order_date
  status
  shipping_method
  carrier
  total {
    subtotal { value currency }
    total_shipping { value currency }
    grand_total { value currency }
    discounts { amount { value currency } label }
  }
  items {
    product_name
    product_sku
    product_url_key
    quantity_ordered
    product_sale_price { value currency }
    product { image { url } }
  }
  payment_methods { name type }
  comments { message timestamp }
  shipping_address {
    firstname
    lastname
    street
    city
    region
    postcode
    telephone
    country_code
  }
  billing_address {
    firstname
    lastname
    street
    city
    region
    postcode
    telephone
    country_code
  }
  invoices { number }
  shipments {
    number
    tracking { title number carrier }
  }
}
''';

  static String _withOrderFields(String operation) =>
      '$operation\n$_orderFields';

  // scope: WEBSITE unifies orders across both store views (`en` / `ar` share
  // one website) — without it `orders` defaults to STORE and each language only
  // sees the orders placed under its own Store header.
  static final String orders = _withOrderFields(r'''
query CustomerOrders($pageSize: Int!, $currentPage: Int!) {
  customer {
    orders(pageSize: $pageSize, currentPage: $currentPage, scope: WEBSITE) {
      total_count
      page_info { current_page total_pages }
      items { ...OrderFields }
    }
  }
}''');

  /// Guest order lookup by the Magento order token (`placeOrder.orderV2.token`)
  /// captured at checkout. Native Magento 2.4.8 query — no custom module.
  static final String guestOrderByToken = _withOrderFields(r'''
query GuestOrderByToken($token: String!) {
  guestOrderByToken(input: { token: $token }) { ...OrderFields }
}''');

  /// Guest order lookup by the details printed on the confirmation e-mail:
  /// order number + the billing e-mail and last name used at checkout. Lets a
  /// guest track an order placed on the website or on another device.
  static final String guestOrder = _withOrderFields(r'''
query GuestOrder($number: String!, $email: String!, $lastname: String!) {
  guestOrder(input: { number: $number, email: $email, lastname: $lastname }) {
    ...OrderFields
  }
}''');

  static const String addresses = r'''
query CustomerAddresses {
  customer {
    addresses {
      id
      firstname
      lastname
      telephone
      street
      city
      postcode
      region { region region_code region_id }
      country_code
      default_shipping
      default_billing
      custom_attributesV2(attributeCodes: ["address_label"]) {
        code
        ... on AttributeSelectedOptions {
          selected_options { label value }
        }
      }
    }
  }
}
''';

  static const String createAddress = r'''
mutation CreateAddress($input: CustomerAddressInput!) {
  createCustomerAddress(input: $input) { id }
}
''';

  static const String updateAddress = r'''
mutation UpdateAddress($id: Int!, $input: CustomerAddressInput!) {
  updateCustomerAddress(id: $id, input: $input) { id }
}
''';

  static const String deleteAddress = r'''
mutation DeleteAddress($id: Int!) {
  deleteCustomerAddress(id: $id)
}
''';

  // --- Saved cards (Magento Vault) -----------------------------------------
  // Core `Magento_VaultGraphQl`, already live on the store. Saved N-Genius
  // cards appear here once the gateway is vault-aware
  // (docs/backend/payment-contract.md §④); until then the list is empty and the
  // whole feature stays hidden. `details` is a JSON string — parsed (and
  // tolerated when malformed) by `SavedCard.fromToken`.
  static const String savedCards = r'''
query CustomerPaymentTokens {
  customerPaymentTokens {
    items {
      public_hash
      payment_method_code
      type
      details
    }
  }
}
''';

  static const String deleteSavedCard = r'''
mutation DeleteSavedCard($publicHash: String!) {
  deletePaymentToken(public_hash: $publicHash) {
    result
  }
}
''';

  static const String updateProfile = r'''
mutation UpdateProfile($input: CustomerUpdateInput!) {
  updateCustomerV2(input: $input) {
    customer { firstname lastname email }
  }
}
''';

  static const String changePassword = r'''
mutation ChangePassword($currentPassword: String!, $newPassword: String!) {
  changeCustomerPassword(
    currentPassword: $currentPassword
    newPassword: $newPassword
  ) {
    email
  }
}
''';

  /// Saves a new mobile number on the signed-in customer (`mobilenumber`,
  /// Vnecoms SMS). The resolver checks [otp] against the code
  /// `customerRegisterSendOtp` sent to that number and fails with "The otp is
  /// not valid." otherwise — so the editor sends the code here directly;
  /// verifying it first with `customerRegisterVerifyOtp` would consume it.
  static const String saveMobile = r'''
mutation SaveMobile($input: MobileCustomerInput!) {
  saveMobileToCustomer(input: $input) { result }
}
''';

  /// Uploads/replaces the signed-in customer's avatar (base64 jpg/png/webp).
  /// MagentoEgypt_PaymentGraphQl; requires the customer bearer token.
  static const String uploadAvatar = r'''
mutation UploadAvatar($file: String!) {
  uploadCustomerAvatar(input: { base64_encoded_file: $file }) { url }
}
''';

  static const String deleteAvatar = r'''
mutation DeleteAvatar {
  deleteCustomerAvatar { url }
}
''';

  /// Discovers the `address_label` select options (Home/Office/Other → their
  /// option ids) so the "Save as" chips map to ids without hardcoding. Labels
  /// are store-scoped.
  static const String addressLabelMetadata = r'''
query AddressLabelMeta {
  customAttributeMetadataV2(
    attributes: [{ attribute_code: "address_label", entity_type: "customer_address" }]
  ) {
    items {
      code
      options { label value }
    }
  }
}
''';
}
