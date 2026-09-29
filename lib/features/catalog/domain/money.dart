import 'package:intl/intl.dart';

/// A monetary value. Prices come pre-localized from Magento `price_range`;
/// we only format the number. Digits are kept **Western** (per design) and the
/// AED code is prefixed, in both EN and AR.
class Money {
  const Money({required this.amount, required this.currency});

  final double amount;
  final String currency;

  static final NumberFormat _format = NumberFormat('#,##0.00', 'en_US');

  String formatted() => '$currency ${_format.format(amount)}';

  @override
  bool operator ==(Object other) =>
      other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);
}
