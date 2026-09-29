import 'dart:convert';

/// A card the customer has stored in Magento's vault (`vault_payment_token`),
/// read through the core `customerPaymentTokens` query.
///
/// The app never sees a PAN, a CVV or the gateway `cardToken` — only the masked
/// display details Magento puts in `PaymentToken.details`. Paying with one is
/// done by handing its [publicHash] back to Magento, which attaches the real
/// token to the N-Genius order server-side (docs/backend/payment-contract.md §④).
class SavedCard {
  const SavedCard({
    required this.publicHash,
    required this.brandCode,
    required this.last4,
    this.expiryMonth,
    this.expiryYear,
  });

  /// Magento's opaque handle for the token — the only identifier that crosses
  /// the wire (`VaultTokenInput.public_hash`).
  final String publicHash;

  /// Magento credit-card type code: `VI`, `MC`, `AE`, … Kept raw because the
  /// set is open-ended and an unknown code must still render.
  final String brandCode;

  /// Last four digits, or empty when the gateway stored something unusable.
  final String last4;

  /// 1–12, and the full year (2028). Null when `details` carried no expiry.
  final int? expiryMonth;
  final int? expiryYear;

  /// Parses one core `PaymentToken`. Returns null for anything the picker
  /// couldn't act on — a non-card token, a missing `public_hash`, or a
  /// `details` blob that isn't the JSON object Magento documents. Card data
  /// arrives from a gateway integration we don't own, so a malformed row must
  /// drop out of the list rather than throw through the whole query.
  static SavedCard? fromToken(Map<String, dynamic> json) {
    final hash = json['public_hash'] as String?;
    if (hash == null || hash.isEmpty) return null;
    // `type` is the PaymentTokenTypeEnum (card | account), not the card brand.
    final tokenType = (json['type'] as String?)?.toLowerCase();
    if (tokenType != null && tokenType != 'card') return null;

    final details = _decodeDetails(json['details'] as String?);
    final expiry = _parseExpiry(details['expirationDate']);
    return SavedCard(
      publicHash: hash,
      brandCode: (details['type'] as String?)?.toUpperCase() ?? '',
      last4: _last4(details['maskedCC']),
      expiryMonth: expiry?.$1,
      expiryYear: expiry?.$2,
    );
  }

  static Map<String, dynamic> _decodeDetails(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } on FormatException {
      return const {};
    }
  }

  /// `maskedCC` is usually already just the last four, but some gateways store
  /// a fully masked pan (`XXXX-XXXX-XXXX-1111`) — keep the trailing digits.
  static String _last4(Object? masked) {
    final digits = (masked?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  /// Magento writes `MM/YYYY`; tolerate `MM/YY` and a datetime, both of which
  /// appear in the wild depending on the vault integration.
  static (int, int)? _parseExpiry(Object? raw) {
    final text = raw?.toString() ?? '';
    if (text.isEmpty) return null;

    final slash = RegExp(r'^(\d{1,2})\s*/\s*(\d{2}|\d{4})$').firstMatch(text);
    if (slash != null) {
      final month = int.parse(slash.group(1)!);
      var year = int.parse(slash.group(2)!);
      if (year < 100) year += 2000;
      return month >= 1 && month <= 12 ? (month, year) : null;
    }

    final iso = RegExp(r'^(\d{4})-(\d{2})').firstMatch(text);
    if (iso != null) {
      final month = int.parse(iso.group(2)!);
      return month >= 1 && month <= 12
          ? (month, int.parse(iso.group(1)!))
          : null;
    }
    return null;
  }

  /// `•••• 1111`, or just the dots when the stored details had no digits.
  String get maskedNumber => last4.isEmpty ? '••••' : '•••• $last4';

  /// `04/28`, or null when no expiry was stored (the row still renders).
  String? get expiryLabel {
    final month = expiryMonth;
    final year = expiryYear;
    if (month == null || year == null) return null;
    return '${month.toString().padLeft(2, '0')}/'
        '${(year % 100).toString().padLeft(2, '0')}';
  }

  /// A card is good through the last day of its expiry month. Unknown expiry
  /// counts as usable — hiding a card we can't date would be worse than letting
  /// the gateway decline it.
  bool isExpiredAt(DateTime now) {
    final month = expiryMonth;
    final year = expiryYear;
    if (month == null || year == null) return false;
    // First day of the following month, in local time like [now].
    return !now.isBefore(DateTime(year, month + 1));
  }

  bool get isExpired => isExpiredAt(DateTime.now());

  /// Display name for the scheme. Falls back to the raw code (and then to a
  /// generic label) so an unmapped brand never renders as an empty string.
  String get brandLabel => switch (brandCode) {
    'VI' => 'Visa',
    'MC' => 'Mastercard',
    'AE' => 'American Express',
    'DI' => 'Discover',
    'DN' => 'Diners Club',
    'JCB' => 'JCB',
    'MI' || 'MD' => 'Maestro',
    'UN' => 'UnionPay',
    '' => 'Card',
    _ => brandCode,
  };
}
