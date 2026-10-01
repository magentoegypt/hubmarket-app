import '../../../core/error/failure.dart';

/// Whether [error] — what a failed `placeOrder` threw — is the store refusing
/// the payment (a declined card, a method that is not available), as opposed to
/// a stock or connection problem. When it is, the message the store gave is the
/// reason (Figma S5 "Reason from bank …"); otherwise null, and checkout shows
/// the usual one-line error instead of the "Payment declined" sheet.
///
/// The store words its refusals in the language of the store view, so the
/// markers are English and Arabic. Hub Market takes no payment online yet (cash
/// on delivery completes on `placeOrder`), so this is the door for the day a
/// gateway is integrated.
String? paymentRefusalReason(Object? error) {
  if (error is! Failure || error.kind != FailureKind.server) return null;
  final detail = error.detail?.trim() ?? '';
  if (detail.isEmpty) return null;
  final text = detail.toLowerCase();
  return _markers.any(text.contains) ? detail : null;
}

const List<String> _markers = [
  'declin',
  'payment',
  'card',
  'transaction',
  'authoriz',
  'authoris',
  'insufficient',
  'رفض',
  'الدفع',
  'بطاقة',
  'معاملة',
  'رصيد',
];
