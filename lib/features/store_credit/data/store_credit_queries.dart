/// Store credit through the Hub Market App backend (`MagentoEgypt_HubAppAccount`,
/// contract `lib/core/graphql/hubapp.graphql`). Every operation needs the
/// customer's token, so they all go out as POST through the authenticated
/// client.
///
/// No variable is declared with an `Hm*` type: inputs are written inline
/// around scalar variables, so a server without the module answers "Cannot
/// query field" (the Build 1 fallback) rather than HTTP 500.
abstract final class StoreCreditQueries {
  /// 20d My credit: the balance, the spending rule and a page of transactions.
  static const String account = r'''
query HmStoreCredit($pageSize: Int!, $currentPage: Int!) {
  hmStoreCredit(pageSize: $pageSize, currentPage: $currentPage) {
    balance { value currency }
    can_use_at_checkout
    total_count
    page_info { current_page page_size total_pages }
    transactions {
      id
      type
      type_label
      amount { value currency }
      balance_after { value currency }
      description
      created_at
    }
  }
}
''';

  /// The Account row's balance: the same query with no transactions.
  static const String balance = r'''
query HmStoreCreditBalance {
  hmStoreCredit(pageSize: 1, currentPage: 1) {
    balance { value currency }
    can_use_at_checkout
  }
}
''';

  /// The cart as the credit row needs it — its credit, its total and the
  /// methods that can pay for it — in the query and both mutations.
  static const String _cartFields = r'''
fragment HmCartCreditFields on Cart {
  id
  hm_store_credit {
    applied { value currency }
    balance { value currency }
    max_applicable { value currency }
    can_use
  }
  prices { grand_total { value currency } }
  available_payment_methods { code title is_deferred }
}
''';

  static String _withCartFields(String operation) => '$operation\n$_cartFields';

  /// The payment step's "Use my credit" row: read when the step opens, once
  /// the shipping method (part of what credit can cover) is on the cart.
  static final String cartCredit = _withCartFields(r'''
query HmCartStoreCredit($cartId: String!) {
  cart(cart_id: $cartId) { ...HmCartCreditFields }
}''');

  /// Uses [amount] of credit on the cart (capped server-side at the order
  /// total); answers the recollected cart.
  static final String apply = _withCartFields(r'''
mutation HmApplyStoreCredit($cartId: String!, $amount: Float!) {
  hmApplyStoreCredit(input: { cart_id: $cartId, amount: $amount }) {
    cart { ...HmCartCreditFields }
  }
}''');

  /// Stops using credit on the cart; answers the recollected cart.
  static final String remove = _withCartFields(r'''
mutation HmRemoveStoreCredit($cartId: String!) {
  hmRemoveStoreCredit(input: { cart_id: $cartId }) {
    cart { ...HmCartCreditFields }
  }
}''');

  /// The credit a placed order used (`sales_order.credit_amount`), for the
  /// totals of order detail and order placed.
  static const String orderCredit = r'''
query HmOrderStoreCredit($number: String!) {
  customer {
    orders(filter: { number: { eq: $number } }, scope: WEBSITE) {
      items {
        number
        total { hm_store_credit { value currency } }
      }
    }
  }
}
''';
}
