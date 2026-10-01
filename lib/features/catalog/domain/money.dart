import 'package:intl/intl.dart';

/// A monetary value. Prices come pre-localized from Magento `price_range`;
/// we only format the number. Digits are kept **Western** in both languages.
///
/// English (and anything until the app says otherwise) prefixes the code:
/// "AED 425". Arabic, as the Arabic frames draw it, puts the dirham sign after
/// the number: "425 د.إ" ([arabic]). Whole amounts drop their decimals, as every
/// Figma frame draws them ("AED 425", "AED 1,250"); an amount with fils keeps
/// both digits ("AED 12.50").
class Money {
  const Money({required this.amount, required this.currency});

  final double amount;
  final String currency;

  /// Whether prices read in Arabic. The app root sets it from the active store
  /// view on every build, so a language switch reaches every price; widget tests
  /// leave it off unless they render Arabic (`captureScreen` follows its `_ar`
  /// name).
  static bool arabic = false;

  static final NumberFormat _format = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _wholeFormat = NumberFormat('#,##0', 'en_US');

  /// The dirham sign of the Arabic format.
  static const String _aedSignAr = 'د.إ';

  /// [exact] keeps the fils of a whole amount too ("AED 120.00"): a ledger
  /// figure such as store credit, unlike a price.
  String formatted({bool exact = false}) {
    final whole = !exact && (amount * 100).round() % 100 == 0;
    final number = (whole ? _wholeFormat : _format).format(amount);
    if (!arabic) return '$currency $number';
    final sign = currency == 'AED' ? _aedSignAr : currency;
    // A right-to-left isolate (U+2067 … U+2069): the number comes first and the
    // sign lies to its left, wherever the surrounding text is laid out — also
    // inside a Text that forces left-to-right and inside an Arabic sentence.
    return '\u2067$number $sign\u2069';
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);
}
