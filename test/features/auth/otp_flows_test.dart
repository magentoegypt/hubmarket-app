import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';

import '../../support/fakes.dart';

({ProviderContainer container, FakeAuthRepository repo, FakeSecureTokenStore tokens})
_setup({bool otpLoginFails = false, bool registrationOtpFails = false}) {
  final repo = FakeAuthRepository(
    otpLoginFails: otpLoginFails,
    registrationOtpFails: registrationOtpFails,
  );
  final tokens = FakeSecureTokenStore();
  final container = ProviderContainer(
    overrides: [
      secureTokenStoreProvider.overrideWithValue(tokens),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, repo: repo, tokens: tokens);
}

void main() {
  group('AuthController — OTP', () {
    test('loginWithOtp authenticates and persists the token', () async {
      final s = _setup();
      await s.container
          .read(authControllerProvider.notifier)
          .loginWithOtp('+971501234567', '123456');

      final state = s.container.read(authControllerProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.customer?.email, 'layla@example.com');
      expect(await s.tokens.read(), 'fake-token');
      expect(s.repo.lastOtpPhone, '+971501234567');
      expect(s.repo.lastOtpCode, '123456');
    });

    test('loginWithOtp propagates a failure on a bad code', () async {
      final s = _setup(otpLoginFails: true);
      await expectLater(
        s.container
            .read(authControllerProvider.notifier)
            .loginWithOtp('+971501234567', '000000'),
        throwsA(isA<Object>()),
      );
      expect(s.container.read(authControllerProvider).isAuthenticated, isFalse);
    });

    test('register forwards the verified mobile number', () async {
      final s = _setup();
      await s.container
          .read(authControllerProvider.notifier)
          .register(
            firstName: 'Sara',
            lastName: 'Ali',
            email: 'sara@example.com',
            password: 'Secret123!',
            mobileNumber: '+971501234567',
          );
      expect(s.repo.lastMobileNumber, '+971501234567');
      // Registration signs the customer in afterwards.
      expect(s.container.read(authControllerProvider).isAuthenticated, isTrue);
    });

    test('a registration resend is marked as one', () async {
      final s = _setup();
      final auth = s.container.read(authControllerProvider.notifier);

      await auth.requestRegistrationOtp('+971501234567');
      expect(s.repo.lastOtpResend, isFalse);

      await auth.requestRegistrationOtp('+971501234567', resend: true);
      expect(s.repo.lastOtpResend, isTrue);
    });

    test('verifyRegistrationOtp surfaces the backend message on a bad code',
        () async {
      final s = _setup(registrationOtpFails: true);
      await expectLater(
        s.container
            .read(authControllerProvider.notifier)
            .verifyRegistrationOtp('+971501234567', '000000'),
        throwsA(isA<Object>()),
      );
    });

    test('a verified reset code buys the ticket the new password is set with',
        () async {
      final s = _setup();
      final auth = s.container.read(authControllerProvider.notifier);

      final ticket = await auth.verifyPasswordResetOtp(
        '+971501234567',
        '123456',
      );
      await auth.resetPassword(
        email: ticket.email,
        token: ticket.token,
        newPassword: 'NewSecret1!',
      );

      expect(s.repo.calls, [
        'verifyPasswordResetOtp:+971501234567:123456',
        'resetPassword:layla@example.com:reset-token',
        // A reset signs the customer in with the new password.
        'login:layla@example.com',
      ]);
      expect(s.repo.lastResetPassword, 'NewSecret1!');
      expect(s.container.read(authControllerProvider).isAuthenticated, isTrue);
    });
  });
}
