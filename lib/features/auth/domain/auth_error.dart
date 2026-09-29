import '../../../core/error/failure.dart';

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
class AuthError {
  const AuthError(this.kind, {this.serverMessage});

  final AuthErrorKind kind;

  /// The store's localized message, kept for [AuthErrorKind.other].
  final String? serverMessage;

  /// Classifies [error] (normally a [Failure]; anything else is `other`).
  factory AuthError.from(Object error) {
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
      kind: AuthErrorKind.tooManyAttempts,
      patterns: [
        RegExp(r'too (much|many)'), // "You are sending OTP too much times."
        RegExp(r'please wait \d+'), // "Please wait 30 seconds before …"
        RegExp(r'أكثر من مرة'), // Vnecoms: لقد قمت بارسال كود التحقق أكثر من مرة
        RegExp(r'محاولات كثيرة|عدد كبير من المحاولات'),
        RegExp(r'يرجى الانتظار \d+|انتظر \d+'),
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
