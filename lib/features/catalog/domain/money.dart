import 'package:intl/intl.dart';

/// A monetary value. Prices come pre-localized from Magento `price_range`;
/// we only format the number. Digits are kept **Western** (per design) and the
/// AED code is prefixed, in both EN and AR.
///
/// Whole amounts drop their decimals, as every Figma frame draws them ("AED 425",
/// "AED 1,250"); an amount with fils keeps both digits ("AED 12.50").
class Money {
  const Money({required this.amount, required this.currency});

  final double amount;
  final String currency;

  static final NumberFormat _format = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _wholeFormat = NumberFormat('#,##0', 'en_US');

  String formatted() {
    final whole = (amount * 100).round() % 100 == 0;
    return '$currency ${(whole ? _wholeFormat : _format).format(amount)}';
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);
}
