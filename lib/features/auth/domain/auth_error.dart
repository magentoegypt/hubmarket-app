import '../../../core/error/failure.dart';
import 'otp_send_status.dart';

/// What went wrong in a sign-in / sign-up / code flow, as the screens need to
/// know it (Figma S6): which field to mark and what to say there.
enum AuthErrorKind {
  /// `generateCustomerToken` refused the e-mail + password. Magento does not
  /// say which one was wrong, nor whether the account exists or is locked.
  wrongCredentials,

  /// No account holds the mobile number (sign-in by code, password reset).
  noAccount,

  /// Another account already holds the mobile number (sign-up, change mobile).
  mobileInUse,

  /// An account with the e-mail already exists (sign-up).
  emailInUse,

  /// The code does not match the one that was sent.
  invalidCode,

  /// The code was right once but has expired (or was already used).
  expiredCode,

  /// Too many codes requested, too many wrong codes, or a resend cooldown.
  tooManyAttempts,

  /// No connection / the request never reached the store.
  offline,

  /// Anything else: [AuthError.serverMessage] carries the store's own
  /// localized text when there is one.
  other,
}

/// A [Failure] from the auth repository, classified by [AuthErrorKind].
///
/// The backends answer refusals in prose, in the store view's language, not
/// with codes: the Vnecoms SMS GraphQL mutations reply `success: false` + `msg`
/// ("The OTP code is not valid.", "كود التحقق غير صالح"), the
/// `MagentoEgypt_SmsExtend` WhatsApp REST endpoints `status: "error"` +
/// `message` ("Mobile number not found.", "Invalid OTP."), and core Magento a
/// GraphQL error ("A customer with the same email address already exists…").
/// So the message is matched against what those modules send, in English and
/// Arabic; anything unrecognised keeps its message and is shown as-is.
///
/// The one exception is the Hub Market App's code request
/// (`hmSendWhatsAppCode`), which says why it refused in a code
/// ([OtpSendRefused.status]): that code picks the error, never the wording.
class AuthError {
  const AuthError(this.kind, {this.serverMessage});

  final AuthErrorKind kind;

  /// The store's localized message, kept for [AuthErrorKind.other].
  final String? serverMessage;

  /// Classifies [error] (normally a [Failure]; anything else is `other`).
  factory AuthError.from(Object error) {
    if (error is OtpSendRefused) return AuthError._fromSendStatus(error);
    if (error is! Failure) return const AuthError(AuthErrorKind.other);
    switch (error.kind) {
      case FailureKind.network:
        return const AuthError(AuthErrorKind.offline);
      case FailureKind.service:
        // An edge / maintenance page: nothing the customer typed is at fault.
        return const AuthError(AuthErrorKind.other);
      case FailureKind.auth:
        // `generateCustomerToken`'s refusal is `graphql-authentication`, which
        // the failure mapper turns into an auth failure with no text.
        final kind = classifyMessage(error.detail);
        return AuthError(kind ?? AuthErrorKind.wrongCredentials);
      case FailureKind.server:
      case FailureKind.unknown:
        final kind = classifyMessage(error.detail);
        if (kind != null) return AuthError(kind);
        final detail = error.detail?.trim();
        return AuthError(
          AuthErrorKind.other,
          // Only a server refusal is worded for customers; an `unknown`
          // failure's detail is a technical trace.
          serverMessage: error.kind == FailureKind.server &&
                  detail != null &&
                  detail.isNotEmpty
              ? detail
              : null,
        );
    }
  }

  /// A refused code request by its `HmOtpSendStatus`: the limits (and a
  /// cooldown, should one ever be refused) read as too many attempts, no
  /// account as no account, a delivery failure as the screen's own "couldn't
  /// send"; a number shared by several accounts or one that can't get codes
  /// has no inline error of its own, so the store's message (which says to
  /// sign in by e-mail) is shown.
  factory AuthError._fromSendStatus(OtpSendRefused error) {
    final detail = error.detail?.trim();
    final message = detail == null || detail.isEmpty ? null : detail;
    return switch (error.status) {
      OtpSendStatus.throttled ||
      OtpSendStatus.cooldown => const AuthError(AuthErrorKind.tooManyAttempts),
      OtpSendStatus.noAccount => const AuthError(AuthErrorKind.noAccount),
      OtpSendStatus.failed => const AuthError(AuthErrorKind.other),
      OtpSendStatus.multiple ||
      OtpSendStatus.undeliverable ||
      OtpSendStatus.sent ||
      OtpSendStatus.masked ||
      OtpSendStatus.unknown => AuthError(
        AuthErrorKind.other,
        serverMessage: message,
      ),
    };
  }

  /// The [AuthErrorKind] a backend message describes, or null when it is not
  /// one the app recognises. Order matters: an e-mail clash is checked before
  /// the generic "already exists".
  static AuthErrorKind? classifyMessage(String? message) {
    final text = message?.trim().toLowerCase();
    if (text == null || text.isEmpty) return null;
    for (final rule in _rules) {
      if (rule.patterns.any((p) => p.hasMatch(text))) return rule.kind;
    }
    return null;
  }

  static final List<({AuthErrorKind kind, List<RegExp> patterns})> _rules = [
    (
      // HubAppAccount's one answer to every refused sign-in code ("That code
      // is incorrect or has expired. Check it, or ask for a new code."): it
      // doesn't say which, so it reads as the more likely of the two, before
      // the "expired" rule claims it.
      kind: AuthErrorKind.invalidCode,
      patterns: [
        RegExp(r'incorrect or has expired'),
        RegExp(r'غير صحيح أو انتهت صلاحيته'),
      ],
    ),
    (
      kind: AuthErrorKind.tooManyAttempts,
      patterns: [
        RegExp(r'too (much|many)'), // "You are sending OTP too much times."
        RegExp(r'please wait \d+'), // "Please wait 30 seconds before …"
        RegExp(r'أكثر من مرة'), // Vnecoms: لقد قمت بارسال كود التحقق أكثر من مرة
        RegExp(r'محاولات كثيرة|عدد كبير من المحاولات'),
        RegExp(r'يرجى الانتظار \d+|انتظر \d+'),
        // HubAppAccount's send limits: "طلبات رموز كثيرة جدًا. …"
        RegExp(r'طلبات رموز كثيرة'),
        // and its lock after five wrong codes (English: "Too many incorrect
        // codes. …"): "رموز غير صحيحة كثيرة جدًا. …"
        RegExp(r'رموز غير صحيحة كثيرة'),
      ],
    ),
    (
      kind: AuthErrorKind.expiredCode,
      patterns: [
        RegExp(r'expired'), // "The OTP code is expired." / "OTP has expired…"
        RegExp(r'انتهت صلاحية'),
      ],
    ),
    (
      kind: AuthErrorKind.invalidCode,
      patterns: [
        RegExp(r'\b(otp|code)\b.*\b(not valid|invalid|incorrect)\b'),
        RegExp(r'\binvalid (otp|code)\b'), // SmsExtend: "Invalid OTP."
        RegExp(r'(كود التحقق|رمز التحقق|otp|الرمز).*غير (صالح|صحيح)'),
      ],
    ),
    (
      kind: AuthErrorKind.emailInUse,
      patterns: [
        RegExp(r'same email address already exists'),
        RegExp(r'email.*already (exists|in use|used)'),
        RegExp(r'البريد الإلكتروني.*(موجود|مستخدم) (بالفعل|مسبقا|مسبقًا)'),
        RegExp(r'يوجد (بالفعل )?عميل بنفس (عنوان )?البريد'),
      ],
    ),
    (
      kind: AuthErrorKind.mobileInUse,
      patterns: [
        // Vnecoms: "The mobile number is used by another customer account."
        RegExp(r'used by another'),
        RegExp(r'mobile number already exists'), // SmsExtend (REGISTER)
        RegExp(r'using this mobile number already'),
        RegExp(r'مستخدم من حساب'),
        RegExp(r'رقم الهاتف موجود بالفعل'),
        RegExp(r'تستخدم نفس رقم'),
      ],
    ),
    (
      kind: AuthErrorKind.noAccount,
      patterns: [
        RegExp(r'mobile number not found'), // SmsExtend (LOGIN / FORGOTPASS)
        RegExp(r'not associated to any customer'), // Vnecoms forgot password
        RegExp(r'customer not found'),
        RegExp(r'لم يتم العثور على (رقم الهاتف|العميل)'),
        RegExp(r'ليس مرتبط'),
        // HubAppAccount, when set to reveal unknown numbers.
        RegExp(r'no account uses this mobile number'),
        RegExp(r'لا يوجد حساب يستخدم'),
      ],
    ),
    (
      kind: AuthErrorKind.wrongCredentials,
      patterns: [
        // generateCustomerToken, should it ever arrive as text.
        RegExp(r'account sign-in was incorrect'),
        RegExp(r'invalid login or password'),
        RegExp(r'البريد الإلكتروني أو كلمة المرور غير صحيحة'),
      ],
    ),
  ];
}
