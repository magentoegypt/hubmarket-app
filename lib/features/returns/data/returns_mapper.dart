import 'dart:convert';

import '../../../core/hubapp/hubapp.dart';
import '../../catalog/data/product_mapper.dart';
import '../../catalog/domain/money.dart';
import '../domain/returns.dart';

/// Contract JSON → return entities. Tolerant, like the shared hm* readers: a
/// missing or mistyped field takes its empty value instead of throwing, so
/// one odd row can't take a whole screen down.

String _string(Object? value) => value is String ? value.trim() : '';

int _int(Object? value) => hmInt(value) ?? 0;

double _double(Object? value) => hmDouble(value) ?? 0;

List<Map<String, dynamic>> _maps(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

ReturnReason? _reason(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final id = _int(json['id']);
  if (id <= 0) return null;
  return ReturnReason(id: id, label: _string(json['label']));
}

Money? _money(Object? json) =>
    moneyFromJson(json is Map<String, dynamic> ? json : null);

ReturnConfig returnConfigFromJson(Map<String, dynamic> json) => ReturnConfig(
  enabled: json['enabled'] == true,
  reasonsEnabled: json['reasons_enabled'] == true,
  otherReasonAllowed: json['other_reason_allowed'] == true,
  partialQuantityAllowed: json['partial_quantity_allowed'] == true,
  reasons: [
    for (final r in _maps(json['reasons']))
      if (_reason(r) case final reason?) reason,
  ],
  policyHtml: hmString(json['policy_html']),
  windowDays: hmInt(json['window_days']),
  attachmentExtensions: [
    for (final extension in hmStrings(json['attachment_extensions']))
      extension.toLowerCase(),
  ],
  attachmentMaxBytes: hmInt(json['attachment_max_bytes']),
  attachmentMaxFiles: hmInt(json['attachment_max_files']) ?? 0,
);

ReturnableItem returnableItemFromJson(Map<String, dynamic> json) {
  // Whole units (the server cuts to an integer), never negative.
  final returnable = _double(json['qty_returnable']).floor();
  return ReturnableItem(
    orderItemId: _int(json['order_item_id']),
    sku: _string(json['sku']),
    name: _string(json['name']),
    imageUrl: hmImageUrl(json['image_url']),
    options: [
      for (final o in _maps(json['options']))
        ReturnOption(label: _string(o['label']), value: _string(o['value'])),
    ],
    qtyOrdered: _double(json['qty_ordered']),
    qtyReturnable: returnable < 0 ? 0 : returnable,
    openReturnNumbers: hmStrings(json['open_return_numbers']),
    seller: HmSellerSummary.fromJson(json['seller']),
    unitPrice: _money(json['unit_price']),
    rowTotal: _money(json['row_total']),
    maxRefund: _money(json['max_refund']),
  );
}

ReturnableOrder returnableOrderFromJson(Map<String, dynamic> json) =>
    ReturnableOrder(
      number: _string(json['order_number']),
      createdAt: _string(json['created_at']),
      statusLabel: _string(json['status_label']),
      items: [
        for (final item in _maps(json['items'])) returnableItemFromJson(item),
      ],
    );

/// Reads a contract page (`items`, `total_count`, `page_info`).
ReturnsPage<T> returnsPageFromJson<T>(
  Map<String, dynamic>? json,
  T Function(Map<String, dynamic>) item, {
  required int requestedPage,
}) {
  final items = [for (final row in _maps(json?['items'])) item(row)];
  final info = json?['page_info'];
  final pageInfo = info is Map<String, dynamic> ? info : const {};
  return ReturnsPage<T>(
    items: items,
    totalCount: hmInt(json?['total_count']) ?? items.length,
    currentPage: hmInt(pageInfo['current_page']) ?? requestedPage,
    totalPages: hmInt(pageInfo['total_pages']) ?? (json == null ? 0 : 1),
  );
}

ReturnSummary returnSummaryFromJson(Map<String, dynamic> json) {
  final first = json['first_item'];
  final firstName = first is Map<String, dynamic> ? _string(first['name']) : '';
  return ReturnSummary(
    id: _int(json['id']),
    number: _string(json['number']),
    orderNumber: _string(json['order_number']),
    createdAt: _string(json['created_at']),
    updatedAt: _string(json['updated_at']),
    state: ReturnState.parse(json['state']),
    statusCode: _string(json['status_code']),
    statusLabel: _string(json['status_label']),
    type: ReturnType.parse(json['type']),
    itemCount: _int(json['item_count']),
    seller: HmSellerSummary.fromJson(json['seller']),
    hasUnreadReply: json['has_unread_reply'] == true,
    refundAmount: _money(json['refund_amount']),
    firstItem: first is Map<String, dynamic> && firstName.isNotEmpty
        ? ReturnSummaryItem(
            name: firstName,
            thumbnail: hmImageUrl(first['thumbnail']),
          )
        : null,
  );
}

/// A message's (or an escalation's) files: `attachments`, else the URLs of
/// `attachment_urls`, named after their last path segment.
List<ReturnAttachment> _attachments(Map<String, dynamic> json) {
  final files = json['attachments'];
  if (files is List) {
    return [
      for (final file in _maps(files))
        if (hmImageUrl(file['url']) case final url?)
          ReturnAttachment(name: _string(file['name']), url: url),
    ];
  }
  return [
    for (final raw in hmStrings(json['attachment_urls']))
      if (hmImageUrl(raw) case final url?)
        ReturnAttachment(
          name: Uri.tryParse(url)?.pathSegments.lastOrNull ?? '',
          url: url,
        ),
  ];
}

ReturnDetail returnDetailFromJson(Map<String, dynamic> json) => ReturnDetail(
  id: _int(json['id']),
  number: _string(json['number']),
  orderNumber: _string(json['order_number']),
  createdAt: _string(json['created_at']),
  updatedAt: _string(json['updated_at']),
  state: ReturnState.parse(json['state']),
  statusCode: _string(json['status_code']),
  statusLabel: _string(json['status_label']),
  type: ReturnType.parse(json['type']),
  reason: _reason(json['reason']),
  otherReason: hmString(json['other_reason']),
  packageOpened: json['package_opened'] == true,
  refundAmountType: RefundAmountType.parse(json['refund_amount_type']),
  refundAmount: moneyFromJson(
    json['refund_amount'] is Map<String, dynamic>
        ? json['refund_amount'] as Map<String, dynamic>
        : null,
  ),
  trackingCode: hmString(json['tracking_code']),
  seller: HmSellerSummary.fromJson(json['seller']),
  items: [
    for (final item in _maps(json['items']))
      ReturnItem(
        orderItemId: _int(item['order_item_id']),
        sku: _string(item['sku']),
        name: _string(item['name']),
        imageUrl: hmImageUrl(item['image_url']),
        quantity: _double(item['quantity']),
      ),
  ],
  history: [
    for (final entry in _maps(json['history']))
      ReturnHistoryEntry(
        statusCode: _string(entry['status_code']),
        statusLabel: _string(entry['status_label']),
        changedBy: ReturnActor.parse(entry['changed_by']),
        createdAt: _string(entry['created_at']),
      ),
  ],
  messages: [
    for (final message in _maps(json['messages']))
      ReturnMessage(
        id: _int(message['id']),
        author: ReturnActor.parse(message['author']),
        authorName: _string(message['author_name']),
        bodyText: _string(message['body_text']),
        attachments: _attachments(message),
        createdAt: _string(message['created_at']),
      ),
  ],
  canReply: json['can_reply'] == true,
  canCancel: json['can_cancel'] == true,
  canEscalate: json['can_escalate'] == true,
  escalation: switch (json['escalation']) {
    final Map<String, dynamic> escalation => ReturnEscalation(
      bodyText: _string(escalation['body_text']),
      attachments: _attachments(escalation),
      createdAt: _string(escalation['created_at']),
    ),
    _ => null,
  },
);

/// `sales_order_item.item_id` behind a core order line uid — Magento encodes
/// it as base64 (`Magento\Framework\GraphQl\Query\Uid`). Null when the uid
/// isn't one. Only for the fallback prices (a server without
/// `HmReturnableItem.unit_price`).
int? orderItemIdFromUid(String uid) {
  try {
    return int.tryParse(utf8.decode(base64.decode(base64.normalize(uid))));
  } on FormatException {
    return null;
  }
}

/// Per-unit refund base of each line of a core `CustomerOrder`, keyed by
/// `order_item_id`: (row total incl. tax − discount) ÷ qty ordered, the
/// server's formula for the refund cap (`OrderLineReader::refundPerUnit`).
/// Lines without the figures are left out.
Map<int, Money> unitRefundsFromOrderJson(Map<String, dynamic>? order) {
  final out = <int, Money>{};
  for (final line in _maps(order?['items'])) {
    final id = orderItemIdFromUid(_string(line['id']));
    final qty = _double(line['quantity_ordered']);
    final prices = line['prices'];
    if (id == null || qty <= 0 || prices is! Map<String, dynamic>) continue;
    final row = prices['row_total_including_tax'];
    if (row is! Map<String, dynamic>) continue;
    final rowValue = hmDouble(row['value']);
    if (rowValue == null) continue;
    final discount = prices['total_item_discount'];
    final discountValue = discount is Map<String, dynamic>
        ? hmDouble(discount['value']) ?? 0
        : 0;
    out[id] = Money(
      amount: (rowValue - discountValue) / qty,
      currency: hmString(row['currency']) ?? 'AED',
    );
  }
  return out;
}
