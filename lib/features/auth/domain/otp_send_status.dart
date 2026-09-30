import '../../../core/error/failure.dart';

/// What a WhatsApp sign-in code request did — `HmOtpSendStatus`, the
/// `status` of `hmSendWhatsAppCode` (Hub Market App backend, HubAppAccount).
///
/// While the store keeps numbers private (the default) only [masked] and
/// [throttled] come back, so nothing tells whether a number has an account;
/// with `hubapp/otp/reveal_unknown_number` on, the store says what happened.
enum OtpSendStatus {
  /// A code went to the account's number.
  sent,

  /// A code went to the number moments ago and still works; no new one was
  /// sent within the resend period.
  cooldown,

  /// Too many requests for the number or the address.
  throttled,

  /// The one answer for every number, account or not.
  masked,

  /// No account uses the number.
  noAccount,

  /// Several accounts use the number (sign in by e-mail).
  multiple,

  /// The account's stored number can't get codes (sign in by e-mail).
  undeliverable,

  /// The code couldn't be sent.
  failed,

  /// A code this app doesn't know yet (a newer backend).
  unknown;

  /// The enum value's GraphQL name, e.g. `NO_ACCOUNT`.
  static OtpSendStatus fromCode(Object? code) => switch (code) {
    'SENT' => sent,
    'COOLDOWN' => cooldown,
    'THROTTLED' => throttled,
    'MASKED' => masked,
    'NO_ACCOUNT' => noAccount,
    'MULTIPLE' => multiple,
    'UNDELIVERABLE' => undeliverable,
    'FAILED' => failed,
    _ => unknown,
  };
}

/// The store turned a sign-in code request down (`sent: false`): [status]
/// says why, [detail] keeps its localized message. `AuthError.from` maps the
/// status to the screen's inline error — the message is never classified.
class OtpSendRefused extends Failure {
  const OtpSendRefused(this.status, {String? message})
    : super(FailureKind.server, detail: message);

  final OtpSendStatus status;

  @override
  String toString() => 'OtpSendRefused(${status.name}: ${detail ?? ''})';
}
