import 'package:intl/intl.dart';

import '../../catalog/domain/money.dart';

/// A store-credit amount as the frames print it: always with its fils, "AED
/// 120.00" — a ledger figure (the balance on Account and My credit, a
/// transaction, what a deletion forfeits), unlike a price, which drops the
/// decimals of a whole amount ([Money.formatted]). Digits stay Western and the
/// code stays in front in both languages, as everywhere in the app.
extension CreditMoney on Money {
  static final NumberFormat _ledger = NumberFormat('#,##0.00', 'en_US');

  String get ledger => '$currency ${_ledger.format(amount)}';
}
