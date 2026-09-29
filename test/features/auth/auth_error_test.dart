import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/auth/domain/auth_error.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_error_text.dart';
import 'package:hubmarket_app/l10n/app_localizations_ar.dart';
import 'package:hubmarket_app/l10n/app_localizations_en.dart';

AuthErrorKind _kind(FailureKind kind, [String? detail]) =>
    AuthError.from(Failure(kind, detail: detail)).kind;

void main() {
  group('AuthError classifies what the backends answer', () {
    test('a refused e-mail sign-in (graphql-authentication)', () {
      // mapOperationException turns generateCustomerToken's refusal into an
      // auth failure with no text.
      expect(_kind(FailureKind.auth), AuthErrorKind.wrongCredentials);
      expect(
        _kind(
          FailureKind.server,
          'The account sign-in was incorrect or your account is disabled '
          'temporarily. Please wait and try again later.',
        ),
        AuthErrorKind.wrongCredentials,
      );
      expect(
        _kind(FailureKind.server, 'البريد الإلكتروني أو كلمة المرور غير صحيحة'),
        AuthErrorKind.wrongCredentials,
      );
    });

    test('no account holds the number', () {
      for (final message in [
        'Mobile number not found.', // SmsExtend (sign-in by code)
        'The mobile number is not associated to any customer account.',
        'لم يتم العثور على رقم الهاتف المحمول.',
        'رقم الهاتف ليس مرتبطاً بأي حساب عميل',
      ]) {
        expect(_kind(FailureKind.server, message), AuthErrorKind.noAccount,
            reason: message);
      }
    });

    test('the number or the e-mail is already taken', () {
      for (final message in [
        'The mobile number is used by another customer account.',
        'Mobile number already exists.',
        'هذا الرقم مستخدم من حساب عميل آخر',
        'رقم الهاتف موجود بالفعل',
      ]) {
        expect(_kind(FailureKind.server, message), AuthErrorKind.mobileInUse,
            reason: message);
      }
      expect(
        _kind(
          FailureKind.server,
          'A customer with the same email address already exists in an '
          'associated website.',
        ),
        AuthErrorKind.emailInUse,
      );
    });

    test('a wrong or expired code', () {
      for (final message in [
        'The OTP code is not valid.', // Vnecoms
        'The otp is not valid.', // saveMobileToCustomer
        'Invalid OTP.', // SmsExtend
        'كود التحقق غير صالح',
        'OTP غير صالح.',
      ]) {
        expect(_kind(FailureKind.server, message), AuthErrorKind.invalidCode,
            reason: message);
      }
      for (final message in [
        'The OTP code is expired.',
        'OTP has expired or does not exist.',
        'انتهت صلاحية كود التحقق',
      ]) {
        expect(_kind(FailureKind.server, message), AuthErrorKind.expiredCode,
            reason: message);
      }
    });

    test('too many attempts, and the resend cooldown', () {
      for (final message in [
        'You are sending OTP too much times.',
        'Too many incorrect attempts. Please request a new code and try '
            'again later.',
        'Please wait 30 seconds before requesting another code.',
        'Too many password reset requests. Please wait and try again.',
        'لقد قمت بارسال كود التحقق أكثر من مرة',
      ]) {
        expect(
          _kind(FailureKind.server, message),
          AuthErrorKind.tooManyAttempts,
          reason: message,
        );
      }
    });

    test('no connection', () {
      expect(_kind(FailureKind.network, 'SocketException'), AuthErrorKind.offline);
    });

    test('anything else keeps the store message, but never a trace', () {
      final server = AuthError.from(
        const Failure(FailureKind.server, detail: 'Invalid input data.'),
      );
      expect(server.kind, AuthErrorKind.other);
      expect(server.serverMessage, 'Invalid input data.');

      final unknown = AuthError.from(
        const Failure(FailureKind.unknown, detail: 'HTTP 404: no route'),
      );
      expect(unknown.kind, AuthErrorKind.other);
      expect(unknown.serverMessage, isNull);

      expect(AuthError.from(StateError('x')).kind, AuthErrorKind.other);
    });
  });

  group('AuthError wording', () {
    final en = AppLocalizationsEn();
    final ar = AppLocalizationsAr();

    test('each kind has its S6 line, in English and Arabic', () {
      expect(
        const AuthError(AuthErrorKind.wrongCredentials).message(en, fallback: '-'),
        'Email or password is incorrect',
      );
      expect(
        const AuthError(AuthErrorKind.wrongCredentials).message(ar, fallback: '-'),
        'البريد الإلكتروني أو كلمة المرور غير صحيحة',
      );
      expect(
        const AuthError(AuthErrorKind.noAccount).message(en, fallback: '-'),
        en.authErrorNoAccount,
      );
      expect(
        const AuthError(AuthErrorKind.invalidCode).message(ar, fallback: '-'),
        ar.authErrorInvalidCode,
      );
      expect(
        const AuthError(AuthErrorKind.tooManyAttempts).message(en, fallback: '-'),
        en.authErrorTooManyAttempts,
      );
      expect(
        const AuthError(AuthErrorKind.offline).message(en, fallback: '-'),
        en.errorNetwork,
      );
    });

    test('unrecognised refusals show the store text, else the fallback', () {
      expect(
        const AuthError(AuthErrorKind.other, serverMessage: 'Nope.')
            .message(en, fallback: 'fallback'),
        'Nope.',
      );
      expect(
        const AuthError(AuthErrorKind.other).message(en, fallback: 'fallback'),
        'fallback',
      );
    });
  });
}
