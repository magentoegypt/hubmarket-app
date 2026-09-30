import '../../../core/hubapp/hubapp.dart';
import '../../catalog/domain/money.dart';

/// Returns (RMA) as the HubAppReturns contract describes them: Figma 23, 23b
/// and 23c. Dates stay the contract's ISO-8601 UTC strings; the screens format
/// them. Sellers are the shared [HmSellerSummary].

/// The outcome the customer asks for (`HmReturnType`).
enum ReturnType {
  refund('REFUND'),
  replace('REPLACE');

  const ReturnType(this.wire);

  final String wire;

  static ReturnType parse(Object? value) =>
      value == 'REPLACE' ? ReturnType.replace : ReturnType.refund;
}

/// How much of a refund is asked for (`HmRefundAmountType`).
enum RefundAmountType {
  full('FULL'),
  custom('CUSTOM');

  const RefundAmountType(this.wire);

  final String wire;

  static RefundAmountType? parse(Object? value) => switch (value) {
    'FULL' => RefundAmountType.full,
    'CUSTOM' => RefundAmountType.custom,
    _ => null,
  };
}

/// Lifecycle (`HmReturnState`). Only an open return takes replies.
enum ReturnState {
  open,
  closed,
  canceled;

  static ReturnState parse(Object? value) => switch (value) {
    'CLOSED' => ReturnState.closed,
    'CANCELED' => ReturnState.canceled,
    _ => ReturnState.open,
  };
}

/// Who wrote a message or changed the status (`HmReturnActor`). Staff are
/// never named: they appear as Hub Market.
enum ReturnActor {
  customer,
  seller,
  hubMarket;

  static ReturnActor parse(Object? value) => switch (value) {
    'CUSTOMER' => ReturnActor.customer,
    'SELLER' => ReturnActor.seller,
    _ => ReturnActor.hubMarket,
  };
}

/// Identifies a line's seller for the one-seller-per-return rule, the way the
/// server groups lines: by vendor, Hub Market's own lines together. Lines
/// whose seller the server didn't send (an unapproved seller) share one
/// group; the server has the final word.
String returnSellerKey(HmSellerSummary? seller) {
  if (seller == null) return '?';
  if (seller.vendorEntityId case final id?) return 'v$id';
  final code = seller.code?.trim() ?? '';
  if (code.isNotEmpty) return 'c${code.toLowerCase()}';
  return seller.isMarketplace ? 'hub' : 'n${seller.name}';
}

class ReturnReason {
  const ReturnReason({required this.id, required this.label});

  final int id;
  final String label;
}

/// The return form's settings (`HmReturnConfig`).
class ReturnConfig {
  const ReturnConfig({
    this.enabled = true,
    this.reasonsEnabled = false,
    this.otherReasonAllowed = false,
    this.partialQuantityAllowed = true,
    this.reasons = const <ReturnReason>[],
    this.policyHtml,
    this.windowDays,
  });

  final bool enabled;

  /// The reason picker is shown, and a reason (listed, or free text where
  /// allowed) is required.
  final bool reasonsEnabled;

  /// A free-text reason is accepted.
  final bool otherReasonAllowed;

  /// Fewer units than the line's remaining quantity may be returned;
  /// otherwise a line goes back whole.
  final bool partialQuantityAllowed;

  final List<ReturnReason> reasons;

  /// The store's return policy (CMS block HTML), null when not published.
  final String? policyHtml;

  /// Always null for signed-in customers: the website has no return window
  /// for them.
  final int? windowDays;

  /// Whether the form offers a reason at all.
  bool get asksForReason =>
      (reasonsEnabled && reasons.isNotEmpty) || otherReasonAllowed;
}

class ReturnOption {
  const ReturnOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// One top-level line of an eligible order (`HmReturnableItem`).
class ReturnableItem {
  const ReturnableItem({
    required this.orderItemId,
    required this.name,
    this.sku = '',
    this.imageUrl,
    this.options = const <ReturnOption>[],
    this.qtyOrdered = 1,
    this.qtyReturnable = 0,
    this.openReturnNumbers = const <String>[],
    this.seller,
  });

  final int orderItemId;
  final String sku;
  final String name;
  final String? imageUrl;
  final List<ReturnOption> options;
  final double qtyOrdered;

  /// Units returnable now, by the website's formula (server-computed).
  final int qtyReturnable;

  /// Non-cancelled returns already holding units of this line.
  final List<String> openReturnNumbers;
  final HmSellerSummary? seller;

  bool get isReturnable => qtyReturnable >= 1;

  String get sellerKey => returnSellerKey(seller);
}

/// An order with at least one returnable line (`HmReturnableOrder`).
class ReturnableOrder {
  const ReturnableOrder({
    required this.number,
    required this.createdAt,
    required this.statusLabel,
    this.items = const <ReturnableItem>[],
  });

  final String number;

  /// Placed, ISO-8601 UTC.
  final String createdAt;
  final String statusLabel;

  /// Every top-level line, returnable or not.
  final List<ReturnableItem> items;

  bool get hasReturnableItem => items.any((i) => i.isReturnable);
}

/// A page of a paged list.
class ReturnsPage<T> {
  const ReturnsPage({
    required this.items,
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
  });

  final List<T> items;
  final int totalCount;
  final int currentPage;
  final int totalPages;

  bool get hasMore => currentPage < totalPages;
}

/// A row of "My returns" (`HmReturnSummary`).
class ReturnSummary {
  const ReturnSummary({
    required this.id,
    required this.number,
    required this.orderNumber,
    required this.createdAt,
    this.updatedAt = '',
    this.state = ReturnState.open,
    this.statusLabel = '',
    this.type = ReturnType.refund,
    this.itemCount = 0,
    this.seller,
    this.hasUnreadReply = false,
  });

  final int id;
  final String number;
  final String orderNumber;
  final String createdAt;
  final String updatedAt;
  final ReturnState state;
  final String statusLabel;
  final ReturnType type;
  final int itemCount;
  final HmSellerSummary? seller;

  /// The seller or Hub Market wrote since the customer last opened it.
  final bool hasUnreadReply;
}

/// A returned line (`HmReturnItem`).
class ReturnItem {
  const ReturnItem({
    required this.orderItemId,
    required this.name,
    this.sku = '',
    this.imageUrl,
    this.quantity = 1,
  });

  final int orderItemId;
  final String sku;
  final String name;
  final String? imageUrl;
  final double quantity;
}

/// A status change (`HmReturnHistoryEntry`).
class ReturnHistoryEntry {
  const ReturnHistoryEntry({
    required this.statusCode,
    required this.statusLabel,
    required this.changedBy,
    required this.createdAt,
  });

  final String statusCode;
  final String statusLabel;
  final ReturnActor changedBy;
  final String createdAt;
}

/// A message of the return's thread (`HmReturnMessage`).
class ReturnMessage {
  const ReturnMessage({
    required this.id,
    required this.author,
    required this.authorName,
    required this.bodyText,
    required this.createdAt,
    this.attachmentUrls = const <String>[],
  });

  final int id;
  final ReturnActor author;

  /// The customer's or the seller's name; "Hub Market" for staff.
  final String authorName;

  /// Plain text (the contract's `body_text`).
  final String bodyText;
  final List<String> attachmentUrls;
  final String createdAt;
}

/// A return with its lines, history and thread (`HmReturn`).
class ReturnDetail {
  const ReturnDetail({
    required this.id,
    required this.number,
    required this.orderNumber,
    required this.createdAt,
    this.updatedAt = '',
    this.state = ReturnState.open,
    this.statusCode = '',
    this.statusLabel = '',
    this.type = ReturnType.refund,
    this.reason,
    this.otherReason,
    this.packageOpened = false,
    this.refundAmountType,
    this.refundAmount,
    this.trackingCode,
    this.seller,
    this.items = const <ReturnItem>[],
    this.history = const <ReturnHistoryEntry>[],
    this.messages = const <ReturnMessage>[],
  });

  final int id;
  final String number;
  final String orderNumber;
  final String createdAt;
  final String updatedAt;
  final ReturnState state;
  final String statusCode;
  final String statusLabel;
  final ReturnType type;
  final ReturnReason? reason;
  final String? otherReason;
  final bool packageOpened;
  final RefundAmountType? refundAmountType;
  final Money? refundAmount;
  final String? trackingCode;
  final HmSellerSummary? seller;
  final List<ReturnItem> items;
  final List<ReturnHistoryEntry> history;
  final List<ReturnMessage> messages;

  /// The website takes replies only while a return is open (open, awaiting
  /// or being reviewed — all `OPEN` here); the server enforces it too.
  bool get acceptsReplies => state == ReturnState.open;

  /// The reason as the customer gave it: a listed reason, else free text.
  String? get reasonText {
    final other = otherReason?.trim() ?? '';
    if (other.isNotEmpty) return other;
    final label = reason?.label.trim() ?? '';
    return label.isEmpty ? null : label;
  }
}
