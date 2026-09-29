import '../../../l10n/l10n.dart';
import '../domain/auth_error.dart';

/// Localized wording for an [AuthError] (Figma S6 and the code screen).
extension AuthErrorText on AuthError {
  /// The line to show under the field / in the banner. Refusals the app does
  /// not recognise keep the store's own (already localized) message, else
  /// [fallback].
  String message(AppLocalizations l10n, {required String fallback}) =>
      switch (kind) {
        AuthErrorKind.wrongCredentials => l10n.authErrorWrongCredentials,
        AuthErrorKind.noAccount => l10n.authErrorNoAccount,
        AuthErrorKind.mobileInUse => l10n.authErrorMobileInUse,
        AuthErrorKind.emailInUse => l10n.authErrorEmailInUse,
        AuthErrorKind.invalidCode => l10n.authErrorInvalidCode,
        AuthErrorKind.expiredCode => l10n.authErrorExpiredCode,
        AuthErrorKind.tooManyAttempts => l10n.authErrorTooManyAttempts,
        AuthErrorKind.offline => l10n.errorNetwork,
        AuthErrorKind.other => serverMessage ?? fallback,
      };
}
