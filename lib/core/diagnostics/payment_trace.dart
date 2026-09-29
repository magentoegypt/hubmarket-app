import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A short, persisted trail of what happened on the last payment attempts.
///
/// Exists because every payment failure used to render as the same "awaiting
/// payment" screen: a missing native module, a resolver that couldn't find the
/// order, a stale token and a PENDING session were indistinguishable from the
/// outside, and `fetchPaymentSession` swallowed the cause into a bare `null`.
/// Diagnosing one bug took a full on-device session for want of a single line.
///
/// Persisted rather than logged because `debugPrint` does not reach logcat in a
/// release build — which is exactly when it is needed. Read it on the
/// connection-test screen (Settings > Connection test).
///
/// Recording must never affect checkout: every call swallows its own errors and
/// nothing here is awaited for correctness.
class PaymentTrace {
  PaymentTrace._();

  static const String _key = 'paymentTrace';

  /// Enough to cover a full attempt (session fetch, gateway, outcome) several
  /// times over, without letting the list grow unbounded.
  static const int _maxEntries = 24;

  /// Serialises writes. Each entry is a read-modify-write of one list, so
  /// concurrent records would drop lines; chaining keeps them ordered without
  /// making callers wait.
  static Future<void> _queue = Future<void>.value();

  /// Records a line. Deliberately returns void rather than a Future: callers
  /// must never await diagnostics. Awaiting this once stalled the payment flow
  /// in widget tests, where SharedPreferences never resolves — a trace line is
  /// never worth blocking a payment, or a test, for.
  static void record(String line) {
    // Mirror to the console too — useful in debug, harmless in release.
    debugPrint('PaymentTrace: $line');
    _queue = _queue.then((_) => _write(line)).catchError((Object _) {});
  }

  static Future<void> _write(String line) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();
      final entries = prefs.getStringList(_key) ?? <String>[];
      entries.insert(0, '${now.substring(5, 19).replaceFirst('T', ' ')}  $line');
      if (entries.length > _maxEntries) {
        entries.removeRange(_maxEntries, entries.length);
      }
      await prefs.setStringList(_key, entries);
    } catch (_) {
      // Diagnostics must never break a payment.
    }
  }

  static Future<List<String>> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // ignore
    }
  }
}
