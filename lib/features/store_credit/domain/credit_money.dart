import '../../catalog/domain/money.dart';

/// A store-credit amount as the frames print it: always with its fils, "AED
/// 120.00" ("120.00 د.إ" in Arabic) — a ledger figure (the balance on Account
/// and My credit, a transaction, what a deletion forfeits), unlike a price,
/// which drops the decimals of a whole amount ([Money.formatted]).
extension CreditMoney on Money {
  String get ledger => formatted(exact: true);
}
