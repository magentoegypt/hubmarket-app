import '../../../core/hubapp/hubapp.dart';
import '../../catalog/domain/money.dart';
import 'return_photo.dart';

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

/// Lifecycle (`HmReturnState`). What the customer may do with a return comes
/// with it (`ReturnDetail.canReply`, `canCancel`, `canEscalate`).
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

/// How a status reads at a glance (the Figma 23b / 23c pills): still being
/// handled, resolved, or refused / cancelled.
enum ReturnTone {
  /// With the store or with Hub Market (amber).
  pending,

  /// Resolved (green).
  resolved,

  /// Cancelled, or refused (red).
  rejected;

  /// From the store's status code first (`status_code`), so that a resolved
  /// return and a rejected one read apart whatever state the store maps its
  /// statuses to; from the state when the code says nothing.
  static ReturnTone of(ReturnState state, String statusCode) {
    final code = statusCode.trim().toLowerCase();
    if (code == 'resolved') return ReturnTone.resolved;
    if (code == 'canceled' ||
        code.contains('reject') ||
        code.contains('declin') ||
        code.contains('refus')) {
      return ReturnTone.rejected;
    }
    return switch (state) {
      ReturnState.open => ReturnTone.pending,
      ReturnState.closed => ReturnTone.resolved,
      ReturnState.canceled => ReturnTone.rejected,
    };
  }
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
    this.attachmentExtensions = const <String>[],
    this.attachmentMaxBytes,
    this.attachmentMaxFiles = 0,
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

  /// File extensions a message may carry, lower case: the website's upload
  /// rules (`attachment_extensions`).
  final List<String> attachmentExtensions;

  /// Largest file in bytes; null when the server didn't say.
  final int? attachmentMaxBytes;

  /// Most files one message may carry; 0 when the server didn't say.
  final int attachmentMaxFiles;

  /// Whether the form offers a reason at all.
  bool get asksForReason =>
      (reasonsEnabled && reasons.isNotEmpty) || otherReasonAllowed;

  /// Whether photos can go with a return, a reply or an escalation: the store
  /// takes one of the image formats the app sends.
  bool get acceptsPhotos =>
      attachmentMaxFiles > 0 &&
      ReturnPhotoFormat.values.any(
        (f) => f.extensions.any(attachmentExtensions.contains),
      );
}

class ReturnOption {
  const ReturnOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// One line of an eligible order the customer can pick (`HmReturnableItem`):
/// a top-level line, or a bundle's child line.
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
    this.unitPrice,
    this.rowTotal,
    this.maxRefund,
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

  /// Paid per unit, the refund cap's base (row total incl. tax − discount) ÷
  /// qty ordered, as the server computes the cap; null from a server that
  /// doesn't send it.
  final Money? unitPrice;

  /// Paid for the whole line (row total incl. tax − discount).
  final Money? rowTotal;

  /// The most a custom refund may ask for this line: [unitPrice] ×
  /// [qtyReturnable].
  final Money? maxRefund;

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

  /// Every line the website's form offers, returnable now or not.
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

/// The line a return's card pictures (`HmReturnSummaryItem`).
class ReturnSummaryItem {
  const ReturnSummaryItem({required this.name, this.thumbnail});

  final String name;
  final String? thumbnail;
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
    this.statusCode = '',
    this.statusLabel = '',
    this.type = ReturnType.refund,
    this.itemCount = 0,
    this.seller,
    this.hasUnreadReply = false,
    this.refundAmount,
    this.firstItem,
  });

  final int id;
  final String number;
  final String orderNumber;
  final String createdAt;
  final String updatedAt;
  final ReturnState state;

  /// The store's status code (`ves_rma_status`), which sets the pill's tone.
  final String statusCode;
  final String statusLabel;
  final ReturnType type;
  final int itemCount;
  final HmSellerSummary? seller;

  /// The seller or Hub Market wrote since the customer last opened it.
  final bool hasUnreadReply;

  /// A refund's amount once the store has one.
  final Money? refundAmount;

  /// The return's first line; null when its order line is gone.
  final ReturnSummaryItem? firstItem;

  ReturnTone get tone => ReturnTone.of(state, statusCode);

  /// The store turned the return down (a status such as "rejected" or
  /// "declined"), rather than the customer cancelling it: the case where
  /// Figma 23b offers "Not happy with the store's answer? Escalate". Only the
  /// detail knows whether it can still be escalated (`can_escalate`); the card
  /// opens it.
  bool get refusedByStore {
    if (state == ReturnState.canceled) return false;
    final code = statusCode.trim().toLowerCase();
    return code.contains('reject') ||
        code.contains('declin') ||
        code.contains('refus');
  }

  /// The same row, read by the customer.
  ReturnSummary markedRead() => ReturnSummary(
    id: id,
    number: number,
    orderNumber: orderNumber,
    createdAt: createdAt,
    updatedAt: updatedAt,
    state: state,
    statusCode: statusCode,
    statusLabel: statusLabel,
    type: type,
    itemCount: itemCount,
    seller: seller,
    refundAmount: refundAmount,
    firstItem: firstItem,
  );
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

/// A file on a message or an escalation (`HmReturnAttachment`).
class ReturnAttachment {
  const ReturnAttachment({required this.name, required this.url});

  /// Image extensions the thread shows as pictures; any other file opens in
  /// the browser, as the website links it.
  static const Set<String> imageExtensions = {
    'jpg',
    'jpeg',
    'jpe',
    'png',
    'gif',
    'bmp',
    'webp',
  };

  final String name;
  final String url;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isImage => imageExtensions.contains(extension);
}

/// A message of the return's thread (`HmReturnMessage`).
class ReturnMessage {
  const ReturnMessage({
    required this.id,
    required this.author,
    required this.authorName,
    required this.bodyText,
    required this.createdAt,
    this.attachments = const <ReturnAttachment>[],
  });

  final int id;
  final ReturnActor author;

  /// The customer's or the seller's name; "Hub Market" for staff.
  final String authorName;

  /// Plain text (the contract's `body_text`).
  final String bodyText;

  /// Its files, in the order sent.
  final List<ReturnAttachment> attachments;
  final String createdAt;
}

/// The customer's escalation to Hub Market (`HmReturnEscalation`), as the
/// website's "RMA Escalate" tab shows it.
class ReturnEscalation {
  const ReturnEscalation({
    required this.bodyText,
    required this.createdAt,
    this.attachments = const <ReturnAttachment>[],
  });

  final String bodyText;
  final List<ReturnAttachment> attachments;
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
    this.canReply = false,
    this.canCancel = false,
    this.canEscalate = false,
    this.escalation,
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

  /// The return takes replies: the server's word (`can_reply`), by the
  /// website's rule — open, awaiting or being reviewed by Hub Market.
  final bool canReply;

  /// The customer may cancel it (`can_cancel`): pending or accepted.
  final bool canCancel;

  /// The customer may ask Hub Market to step in (`can_escalate`): not
  /// cancelled and never escalated.
  final bool canEscalate;

  /// The customer's escalation, once there is one.
  final ReturnEscalation? escalation;

  ReturnTone get tone => ReturnTone.of(state, statusCode);

  /// The reason as the customer gave it: a listed reason, else free text.
  String? get reasonText {
    final other = otherReason?.trim() ?? '';
    if (other.isNotEmpty) return other;
    final label = reason?.label.trim() ?? '';
    return label.isEmpty ? null : label;
  }
}
