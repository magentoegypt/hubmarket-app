import '../../../core/hubapp/hubapp_models.dart';
import '../../marketplace/data/seller_selections.dart';

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
  id
  number
  token
  available_actions
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
    selected_options { label value }
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

  /// Each line's seller (HubAppVendors `hm_seller`), which the order detail
  /// groups items by. GraphQL merges these `items` with [_orderFields]'.
  static const String hmOrderSellers = r'''
fragment HmOrderSellers on CustomerOrder {
  items {
    hm_seller {
      ...HmSellerFields
    }
  }
}
''';

  /// The HubApp twin of an order [document]: `...HmOrderSellers` beside each
  /// `...OrderFields`. Sent only while HubApp serves `hm_seller`; today's
  /// server gets [document] itself — see `SellerSelections`.
  static String withSellers(String document) => SellerSelections.beside(
    document,
    anchor: 'OrderFields',
    spread: 'HmOrderSellers',
    fragments: '$hmOrderSellers\n${HmFragments.seller}\n${HmFragments.link}',
  );

  /// The order split by store (HubAppOrders `hm_packages`, Figma 22): each
  /// store's status, shipments with their tracking, totals and the comments
  /// it made visible. `items { id }` is what `item_uids` points at; GraphQL
  /// merges these `items` with [_orderFields]'.
  static const String hmOrderPackages = r'''
fragment HmOrderPackages on CustomerOrder {
  items { id }
  hm_packages {
    seller { ...HmSellerFields }
    status_code
    status_label
    state
    item_uids
    subtotal { value currency }
    discount { value currency }
    tax { value currency }
    shipping_amount { value currency }
    shipping_method
    grand_total { value currency }
    shipments {
      id
      number
      created_at
      tracks { carrier_code carrier_title number tracking_url }
    }
    comments { message created_at }
  }
}
''';

  /// [document] with `...HmOrderPackages` beside each `...OrderFields`; sent
  /// only while HubApp serves `hm_packages` (see [withHubApp]).
  static String withPackages(String document) => SellerSelections.beside(
    document,
    anchor: 'OrderFields',
    spread: 'HmOrderPackages',
    fragments: '$hmOrderPackages\n${HmFragments.seller}\n${HmFragments.link}',
  );

  /// The order [document] as the server can take it: plus each line's seller
  /// when [sellers], plus the per-store packages when [packages]; [document]
  /// itself when neither (today's server).
  static String withHubApp(
    String document, {
    required bool sellers,
    required bool packages,
  }) {
    var twin = document;
    if (sellers) twin = withSellers(twin);
    if (packages) twin = withPackages(twin);
    return twin;
  }

  // scope: WEBSITE unifies orders across both store views (`en` / `ar` share
  // one website) — without it `orders` defaults to STORE and each language only
  // sees the orders placed under its own Store header. Newest first: without a
  // sort Magento returns orders in database order, oldest first.
  static final String orders = _withOrderFields(r'''
query CustomerOrders($pageSize: Int!, $currentPage: Int!) {
  customer {
    orders(
      pageSize: $pageSize
      currentPage: $currentPage
      scope: WEBSITE
      sort: { sort_field: CREATED_AT, sort_direction: DESC }
    ) {
      total_count
      page_info { current_page total_pages }
      items { ...OrderFields }
    }
  }
}''');

  /// One of the signed-in customer's orders by its number (the increment id
  /// customers see, e.g. `000000248`): an order opened from a push, a link or
  /// Order placed. `scope: WEBSITE` for the same reason as [orders].
  static final String orderByNumber = _withOrderFields(r'''
query CustomerOrderByNumber($number: String!) {
  customer {
    orders(filter: { number: { eq: $number } }, pageSize: 1, scope: WEBSITE) {
      items { ...OrderFields }
    }
  }
}''');

  /// The customer's newest orders, newest first (both store views), for the
  /// Home's active-order card. The sort is explicit: without one Magento
  /// returns orders in database order, oldest first.
  static final String recentOrders = _withOrderFields(r'''
query CustomerRecentOrders($pageSize: Int!) {
  customer {
    orders(
      pageSize: $pageSize
      currentPage: 1
      scope: WEBSITE
      sort: { sort_field: CREATED_AT, sort_direction: DESC }
    ) {
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

  /// Core order cancellation (Magento_OrderCancellationGraphQl). `order_id`
  /// is `CustomerOrder.id`; `reason` must be one of storeConfig
  /// `order_cancellation_reasons`. Refusals come back in `errorV2`, not as
  /// GraphQL errors.
  static final String cancelOrder = _withOrderFields(r'''
mutation CancelOrder($orderId: ID!, $reason: String!) {
  cancelOrder(input: { order_id: $orderId, reason: $reason }) {
    error
    errorV2 { code message }
    order { ...OrderFields }
  }
}''');

  /// A guest's cancellation request: Magento e-mails the billing address a
  /// link that confirms it (`confirmCancelOrder`); nothing is cancelled yet.
  /// `token` is the order's `CustomerOrder.token`.
  static const String requestGuestOrderCancel = r'''
mutation RequestGuestOrderCancel($token: String!, $reason: String!) {
  requestGuestOrderCancel(input: { token: $token, reason: $reason }) {
    error
    errorV2 { code message }
  }
}
''';

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
  // Core `Magento_VaultGraphQl`, already live on the store. Cards appear here
  // once Hub Market runs a vault-aware card gateway; until then the list is
  // empty and the whole feature stays hidden. `details` is a JSON string — parsed (and
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

  /// The newsletter opt-in on the customer account (Customers › Newsletter).
  static const String newsletterStatus = r'''
query CustomerNewsletter {
  customer { is_subscribed }
}
''';

  static const String setNewsletter = r'''
mutation SetNewsletter($subscribed: Boolean!) {
  updateCustomerV2(input: { is_subscribed: $subscribed }) {
    customer { is_subscribed }
  }
}
''';

  /// The store's contact form (core `contactUs`): Magento e-mails the message
  /// to the store's contact address. Gated by storeConfig `contact_enabled`.
  static const String contactUs = r'''
mutation ContactUs($input: ContactUsInput!) {
  contactUs(input: $input) { status }
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
