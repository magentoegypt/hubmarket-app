import '../../../core/hubapp/hubapp.dart';

/// GraphQL for returns: the HubAppReturns contract (`hmReturnConfig`,
/// `hmReturnableOrders`, `hmReturnableOrder`, `hmReturns`, `hmReturn`,
/// `hmCreateReturn`, `hmAddReturnMessage`, `hmEscalateReturn`,
/// `hmCancelReturn`) plus one core query, the fallback for line prices. Every
/// one of them needs the customer token, so they go on the authenticated
/// client, as POST.
///
/// Variables stay scalar wherever the contract allows: while the module is
/// missing, Magento answers a variable of an unknown `Hm*` type with HTTP 500
/// instead of "Cannot query field". The documents that declare one —
/// `hmCreateReturn`'s `HmCreateReturnInput`, and the photos
/// (`[HmReturnAttachmentInput!]`) of a reply or an escalation — are only ever
/// sent after a query of the same module answered: the form can't be filled
/// in, nor a return's page opened, before `hmReturnConfig` / `hmReturn` did.
abstract final class ReturnsQueries {
  static const String _attachmentFields = r'''
fragment HmReturnAttachmentFields on HmReturnAttachment {
  name
  url
}
''';

  static const String _returnFields = r'''
fragment HmReturnFields on HmReturn {
  id
  number
  order_number
  created_at
  updated_at
  state
  status_code
  status_label
  type
  reason { id label }
  other_reason
  package_opened
  refund_amount_type
  refund_amount { value currency }
  tracking_code
  seller { ...HmSellerFields }
  items { order_item_id sku name image_url quantity }
  history { status_code status_label changed_by created_at }
  messages {
    id
    author
    author_name
    body_text
    attachments { ...HmReturnAttachmentFields }
    created_at
  }
  can_reply
  can_cancel
  can_escalate
  escalation {
    body_text
    attachments { ...HmReturnAttachmentFields }
    created_at
  }
}
''';

  static const String _returnableOrderFields = r'''
fragment HmReturnableOrderFields on HmReturnableOrder {
  order_number
  created_at
  status_label
  items {
    order_item_id
    sku
    name
    image_url
    options { label value }
    qty_ordered
    qty_returnable
    open_return_numbers
    seller { ...HmSellerFields }
    unit_price { value currency }
    row_total { value currency }
    max_refund { value currency }
  }
}
''';

  /// The shared seller fragment and the link fragment it spreads.
  static String _withSeller(String operation) =>
      '$operation\n${HmFragments.seller}\n${HmFragments.link}';

  static String _withReturn(String operation) =>
      _withSeller('$operation\n$_returnFields\n$_attachmentFields');

  static String _withReturnableOrder(String operation) =>
      _withSeller('$operation\n$_returnableOrderFields');

  /// Form settings, reasons and what files a message may carry, in the Store
  /// header's language.
  static const String config = r'''
query HmReturnConfig {
  hmReturnConfig {
    enabled
    reasons_enabled
    other_reason_allowed
    partial_quantity_allowed
    reasons { id label }
    policy_html
    window_days
    attachment_extensions
    attachment_max_bytes
    attachment_max_files
  }
}
''';

  /// The customer's orders with a returnable line, newest first, each with
  /// every line the website's form offers and what is returnable of it
  /// (pageSize 1–20).
  static final String returnableOrders = _withReturnableOrder(r'''
query HmReturnableOrders($pageSize: Int!, $currentPage: Int!) {
  hmReturnableOrders(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page total_pages }
    items { ...HmReturnableOrderFields }
  }
}''');

  /// One of the customer's orders as [returnableOrders] lists it; null when
  /// it has nothing left to return.
  static final String returnableOrder = _withReturnableOrder(r'''
query HmReturnableOrder($number: String!) {
  hmReturnableOrder(order_number: $number) { ...HmReturnableOrderFields }
}''');

  /// The customer's returns, newest first (pageSize 1–50).
  static final String returns = _withSeller(r'''
query HmReturns($pageSize: Int!, $currentPage: Int!) {
  hmReturns(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page total_pages }
    items {
      id
      number
      order_number
      created_at
      updated_at
      state
      status_code
      status_label
      type
      item_count
      has_unread_reply
      seller { ...HmSellerFields }
      refund_amount { value currency }
      first_item { name thumbnail }
    }
  }
}''');

  /// One of the customer's returns; null when it isn't theirs. Reading it
  /// marks it read for the customer.
  static final String returnDetail = _withReturn(r'''
query HmReturn($id: Int!) {
  hmReturn(id: $id) { ...HmReturnFields }
}''');

  /// Files a return for one seller's lines of one order, with its photos.
  static final String createReturn = _withReturn(r'''
mutation HmCreateReturn($input: HmCreateReturnInput!) {
  hmCreateReturn(input: $input) {
    rma { ...HmReturnFields }
  }
}''');

  /// The customer's reply on an open return (input inlined: scalar
  /// variables only).
  static final String addMessage = _withReturn(r'''
mutation HmAddReturnMessage($returnId: Int!, $message: String!) {
  hmAddReturnMessage(input: { return_id: $returnId, message: $message }) {
    rma { ...HmReturnFields }
  }
}''');

  /// [addMessage] with photos.
  static final String addMessageWithPhotos = _withReturn(r'''
mutation HmAddReturnMessageWithPhotos(
  $returnId: Int!
  $message: String!
  $attachments: [HmReturnAttachmentInput!]!
) {
  hmAddReturnMessage(
    input: { return_id: $returnId, message: $message, attachments: $attachments }
  ) {
    rma { ...HmReturnFields }
  }
}''');

  /// Asks Hub Market to step in (input inlined: scalar variables only).
  static final String escalate = _withReturn(r'''
mutation HmEscalateReturn($returnId: Int!, $message: String!) {
  hmEscalateReturn(input: { return_id: $returnId, message: $message }) {
    rma { ...HmReturnFields }
  }
}''');

  /// [escalate] with photos.
  static final String escalateWithPhotos = _withReturn(r'''
mutation HmEscalateReturnWithPhotos(
  $returnId: Int!
  $message: String!
  $attachments: [HmReturnAttachmentInput!]!
) {
  hmEscalateReturn(
    input: { return_id: $returnId, message: $message, attachments: $attachments }
  ) {
    rma { ...HmReturnFields }
  }
}''');

  /// Cancels a pending or accepted return (input inlined).
  static final String cancel = _withReturn(r'''
mutation HmCancelReturn($returnId: Int!) {
  hmCancelReturn(input: { return_id: $returnId }) {
    rma { ...HmReturnFields }
  }
}''');

  /// Core order lines with what the refund cap is made of: the fallback for
  /// a server whose `HmReturnableItem` has no `unit_price`. `id` is the
  /// line's uid (base64 of `sales_order_item.item_id`, Magento's `Uid`
  /// encoder), which ties it to `HmReturnableItem.order_item_id`.
  static const String orderLinePrices = r'''
query ReturnOrderLinePrices($number: String!) {
  customer {
    orders(filter: { number: { eq: $number } }, scope: WEBSITE, pageSize: 1) {
      items {
        number
        items {
          id
          quantity_ordered
          prices {
            row_total_including_tax { value currency }
            total_item_discount { value currency }
          }
        }
      }
    }
  }
}
''';
}
