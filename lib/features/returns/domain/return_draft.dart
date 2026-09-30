import '../../../core/hubapp/hubapp.dart';
import 'returns.dart';

/// Why a line on the return form (Figma 23) can or can't be ticked.
enum LineAvailability {
  /// Ticked.
  selected,

  /// Can be ticked.
  available,

  /// Nothing left to return: already held by other returns, or not invoiced
  /// yet.
  unavailable,

  /// Sold by another seller than the lines already ticked — one seller per
  /// return (the website's rule).
  otherSeller,
}

/// Something the form can't send yet.
enum ReturnFormError {
  items,
  reason,
  otherReasonTooLong,
  packageOpened,
  customAmount,
  customAmountOverCap,
  comment,
  commentTooLong,
  trackingTooLong,
}

/// What the customer has filled in on the return form, the website's rules
/// the app can check before sending, and the `HmCreateReturnInput` it
/// becomes. Immutable: every change returns a new draft.
///
/// The server checks all of it again (eligibility, quantities, the seller,
/// the refund cap, ownership); these checks only save a round trip.
class ReturnDraft {
  const ReturnDraft({
    required this.order,
    this.quantities = const <int, int>{},
    this.type = ReturnType.refund,
    this.reasonId,
    this.otherReasonSelected = false,
    this.otherReason = '',
    this.packageOpened,
    this.refundAmountType = RefundAmountType.full,
    this.customAmount = '',
    this.comment = '',
    this.trackingCode = '',
  });

  /// Limits the server enforces (EligibilityService).
  static const int maxCommentLength = 5000;
  static const int maxOtherReasonLength = 255;
  static const int maxTrackingLength = 255;

  final ReturnableOrder order;

  /// Ticked lines: `order_item_id` → units to return.
  final Map<int, int> quantities;
  final ReturnType type;

  /// A listed reason, unless [otherReasonSelected].
  final int? reasonId;

  /// The customer is writing their own reason ([otherReason]).
  final bool otherReasonSelected;
  final String otherReason;

  /// Null until the customer answers.
  final bool? packageOpened;

  /// Refunds only: the full amount, or [customAmount].
  final RefundAmountType refundAmountType;

  /// As typed; see [customAmountValue].
  final String customAmount;
  final String comment;
  final String trackingCode;

  ReturnDraft copyWith({
    Map<int, int>? quantities,
    ReturnType? type,
    int? reasonId,
    bool clearReason = false,
    bool? otherReasonSelected,
    String? otherReason,
    bool? packageOpened,
    RefundAmountType? refundAmountType,
    String? customAmount,
    String? comment,
    String? trackingCode,
  }) => ReturnDraft(
    order: order,
    quantities: quantities ?? this.quantities,
    type: type ?? this.type,
    reasonId: clearReason ? null : (reasonId ?? this.reasonId),
    otherReasonSelected: otherReasonSelected ?? this.otherReasonSelected,
    otherReason: otherReason ?? this.otherReason,
    packageOpened: packageOpened ?? this.packageOpened,
    refundAmountType: refundAmountType ?? this.refundAmountType,
    customAmount: customAmount ?? this.customAmount,
    comment: comment ?? this.comment,
    trackingCode: trackingCode ?? this.trackingCode,
  );

  bool get hasSelection => quantities.isNotEmpty;

  /// The ticked lines, in the order's line order.
  List<ReturnableItem> get selectedItems => [
    for (final item in order.items)
      if (quantities.containsKey(item.orderItemId)) item,
  ];

  /// The seller every ticked line belongs to; null with nothing ticked.
  String? get sellerKey {
    final items = selectedItems;
    return items.isEmpty ? null : items.first.sellerKey;
  }

  /// The seller of the ticked lines, when the server named one.
  HmSellerSummary? get seller {
    final items = selectedItems;
    return items.isEmpty ? null : items.first.seller;
  }

  LineAvailability availabilityOf(ReturnableItem item) {
    if (quantities.containsKey(item.orderItemId)) {
      return LineAvailability.selected;
    }
    if (!item.isReturnable) return LineAvailability.unavailable;
    final key = sellerKey;
    if (key != null && key != item.sellerKey) {
      return LineAvailability.otherSeller;
    }
    return LineAvailability.available;
  }

  /// The fewest units of [item] the customer may return: one when partial
  /// quantities are allowed, otherwise everything that's left.
  static int minQuantity(ReturnableItem item, ReturnConfig config) =>
      config.partialQuantityAllowed ? 1 : item.qtyReturnable;

  /// Ticks or unticks [item]. A newly ticked line starts at everything that
  /// is left, as the website's form does; a line that can't be ticked (see
  /// [availabilityOf]) leaves the draft unchanged.
  ReturnDraft toggle(ReturnableItem item) {
    final next = Map<int, int>.of(quantities);
    switch (availabilityOf(item)) {
      case LineAvailability.selected:
        next.remove(item.orderItemId);
      case LineAvailability.available:
        next[item.orderItemId] = item.qtyReturnable;
      case LineAvailability.unavailable:
      case LineAvailability.otherSeller:
        return this;
    }
    return copyWith(quantities: next);
  }

  /// Sets a ticked line's quantity, kept within what [config] allows for it
  /// (see [minQuantity]) and never above what's left.
  ReturnDraft setQuantity(
    ReturnableItem item,
    int quantity,
    ReturnConfig config,
  ) {
    if (!quantities.containsKey(item.orderItemId)) return this;
    final min = minQuantity(item, config);
    final max = item.qtyReturnable;
    final clamped = quantity < min ? min : (quantity > max ? max : quantity);
    return copyWith(quantities: {...quantities, item.orderItemId: clamped});
  }

  /// [customAmount] as a number: Arabic-Indic digits and a comma or Arabic
  /// decimal separator are accepted. Null when it isn't a number.
  double? get customAmountValue {
    final western = customAmount.trim().replaceAllMapped(
      RegExp('[\u0660-\u0669\u06F0-\u06F9\u066B,]'),
      (m) {
        final code = m.group(0)!.codeUnitAt(0);
        if (code == 0x066B || code == 0x2C) return '.';
        return '${code >= 0x06F0 ? code - 0x06F0 : code - 0x0660}';
      },
    );
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(western)) return null;
    return double.tryParse(western);
  }

  /// The most a custom refund may ask for: each ticked line's
  /// (row total incl. tax − discount) ÷ qty ordered × units returned, as the
  /// server computes it, in [unitRefunds] (`order_item_id` → per-unit
  /// amount). Rounded down to the cent. Null when nothing is ticked or a
  /// ticked line's amount is unknown.
  double? refundCap(Map<int, double> unitRefunds) {
    if (quantities.isEmpty) return null;
    var sum = 0.0;
    for (final entry in quantities.entries) {
      final unit = unitRefunds[entry.key];
      if (unit == null) return null;
      sum += unit * entry.value;
    }
    return (sum * 100 + 1e-6).floorToDouble() / 100;
  }

  /// Whether the reason is required by [config]: reasons are on and there
  /// is something to pick or write.
  static bool reasonRequired(ReturnConfig config) =>
      config.reasonsEnabled &&
      (config.reasons.isNotEmpty || config.otherReasonAllowed);

  /// What stops the draft from being sent; empty when it can go.
  /// [refundCap] is [ReturnDraft.refundCap], when known.
  Set<ReturnFormError> validate(ReturnConfig config, {double? refundCap}) {
    final errors = <ReturnFormError>{};
    if (quantities.isEmpty) errors.add(ReturnFormError.items);

    final other = otherReason.trim();
    if (otherReasonSelected) {
      if (other.isEmpty && reasonRequired(config)) {
        errors.add(ReturnFormError.reason);
      } else if (other.length > maxOtherReasonLength) {
        errors.add(ReturnFormError.otherReasonTooLong);
      }
    } else if (reasonId == null && reasonRequired(config)) {
      errors.add(ReturnFormError.reason);
    }

    if (packageOpened == null) errors.add(ReturnFormError.packageOpened);

    if (type == ReturnType.refund &&
        refundAmountType == RefundAmountType.custom) {
      final value = customAmountValue;
      if (value == null || value <= 0) {
        errors.add(ReturnFormError.customAmount);
      } else if (refundCap != null && value > refundCap + 0.00001) {
        errors.add(ReturnFormError.customAmountOverCap);
      }
    }

    final text = comment.trim();
    if (text.isEmpty) {
      errors.add(ReturnFormError.comment);
    } else if (text.length > maxCommentLength) {
      errors.add(ReturnFormError.commentTooLong);
    }
    if (trackingCode.trim().length > maxTrackingLength) {
      errors.add(ReturnFormError.trackingTooLong);
    }
    return errors;
  }

  /// The `HmCreateReturnInput` for this draft. Lines keep the order's line
  /// order; the refund fields go only with a refund, the custom amount only
  /// with a custom refund, and empty optional text is left out.
  Map<String, dynamic> toInput() {
    final other = otherReason.trim();
    final tracking = trackingCode.trim();
    return <String, dynamic>{
      'order_number': order.number,
      'items': [
        for (final item in selectedItems)
          <String, dynamic>{
            'order_item_id': item.orderItemId,
            'quantity': quantities[item.orderItemId]!.toDouble(),
          },
      ],
      'type': type.wire,
      if (!otherReasonSelected && reasonId != null) 'reason_id': reasonId,
      if (otherReasonSelected && other.isNotEmpty) 'other_reason': other,
      'package_opened': packageOpened ?? false,
      'comment': comment.trim(),
      if (type == ReturnType.refund) ...{
        'refund_amount_type': refundAmountType.wire,
        if (refundAmountType == RefundAmountType.custom)
          'refund_custom_amount': customAmountValue,
      },
      if (tracking.isNotEmpty) 'tracking_code': tracking,
    };
  }
}
