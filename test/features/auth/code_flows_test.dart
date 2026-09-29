import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_widgets.dart';

import 'auth_harness.dart';

const _typed = '050 123 4567';
const _e164 = '+971501234567';

Future<void> _drainCountdown(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 61));

/// Every WhatsApp-code flow reaches "05 Verify WhatsApp code" and makes the
/// calls it made before the screen existed: the send on the form, the check
/// (and the follow-up) on the Verify screen.
void main() {
  testWidgets('sign in by code: REST send, then verify signs in and lands Home',
      (tester) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _typed);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyCodeScreen), findsOneWidget);
    expect(harness.repo.calls, ['requestLoginOtp:$_e164']);

    // Resend goes through the same sign-in send.
    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text('Resend code'));
    await tester.pump();
    expect(harness.repo.calls.last, 'requestLoginOtp:$_e164');

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();

    expect(harness.repo.calls.last, 'loginWithOtp:$_e164:123456');
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('"Continue with WhatsApp code" opens the Mobile tab', (
    tester,
  ) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue with WhatsApp code'));
    await tester.pumpAndSettle();

    expect(find.text('Mobile number (WhatsApp)'), findsOneWidget);
    expect(find.text('Send WhatsApp code'), findsOneWidget);
  });

  testWidgets('"Use email instead" returns to the Email tab', (tester) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _typed);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use email instead'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyCodeScreen), findsNothing);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
  });

  testWidgets(
    'register: Vnecoms send, verify, then createCustomer with the number',
    (tester) async {
      useTallView(tester);
      final harness = AuthHarness();
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signUp));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Sara');
      await tester.enterText(fields.at(1), 'Ahmed');
      await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(3), _typed);
      await tester.enterText(fields.at(4), 'Sara@2026x');
      await tester.tap(find.byType(AuthCheckRow).first); // terms
      await tester.tap(find.byType(AuthCheckRow).last); // offers
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      expect(harness.repo.calls, ['requestRegistrationOtp:$_e164']);
      expect(find.text('Use email instead'), findsNothing);

      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      expect(harness.repo.calls.last, 'requestRegistrationOtp:$_e164:resend');

      await tester.enterText(find.byType(TextField), '654321');
      await tester.pumpAndSettle();

      expect(harness.repo.calls.sublist(2), [
        'verifyRegistrationOtp:$_e164:654321',
        'register:sara.ahmed@gmail.com:$_e164',
        'login:sara.ahmed@gmail.com',
      ]);
      expect(harness.repo.lastSubscribeToNewsletter, isTrue);
      expect(find.text('HOME'), findsOneWidget);
    },
  );

  testWidgets('register waits for the code: a back from Verify creates nothing',
      (tester) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signUp));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Sara');
    await tester.enterText(fields.at(1), 'Ahmed');
    await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
    await tester.enterText(fields.at(3), _typed);
    await tester.enterText(fields.at(4), 'Sara@2026x');
    await tester.tap(find.byType(AuthCheckRow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change number'));
    await tester.pumpAndSettle();

    expect(harness.repo.calls, ['requestRegistrationOtp:$_e164']);
    expect(find.text('Create account'), findsWidgets); // back on the form
  });

  testWidgets(
    'forgot password by code: send, verify, then the new-password step',
    (tester) async {
      useTallView(tester);
      final harness = AuthHarness();
      await tester.pumpWidget(
        harness.build(initialLocation: AppRoutes.forgotPassword),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _typed);
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();

      expect(harness.repo.calls, ['requestPasswordResetOtp:$_e164']);
      await tester.pump(const Duration(seconds: 60));
      await tester.tap(find.text('Resend code'));
      await tester.pump();
      expect(harness.repo.calls.last, 'requestPasswordResetOtp:$_e164:resend');

      await tester.enterText(find.byType(TextField), '111222');
      await tester.pumpAndSettle();

      expect(
        harness.repo.calls.last,
        'verifyPasswordResetOtp:$_e164:111222',
      );
      expect(find.byType(ResetPasswordScreen), findsOneWidget);

      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2), reason: 'the ticket fills e-mail/token');
      await tester.enterText(fields.at(0), 'NewPass#2026');
      await tester.enterText(fields.at(1), 'NewPass#2026');
      await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
      await tester.pumpAndSettle();

      expect(harness.repo.calls.sublist(harness.repo.calls.length - 2), [
        'resetPassword:layla@example.com:reset-token',
        'login:layla@example.com',
      ]);
      expect(harness.repo.lastResetPassword, 'NewPass#2026');
      expect(find.text('HOME'), findsOneWidget);
    },
  );

  testWidgets('forgot password by e-mail still sends the link', (tester) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(
      harness.build(initialLocation: AppRoutes.forgotPassword),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sara.ahmed@gmail.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(harness.repo.calls, ['requestPasswordReset:sara.ahmed@gmail.com']);
    expect(
      find.text('If that email is registered, a reset link is on its way.'),
      findsOneWidget,
    );
  });

  testWidgets('change mobile: registration send, then saveMobileToCustomer', (
    tester,
  ) async {
    useTallView(tester);
    final harness = AuthHarness(signedIn: true);
    await tester.pumpWidget(harness.build(initialLocation: editMobileRoute));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), _typed);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyCodeScreen), findsOneWidget);
    expect(harness.repo.calls, ['requestRegistrationOtp:$_e164']);
    expect(find.text('Use email instead'), findsNothing);

    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text('Resend code'));
    await tester.pump();
    expect(harness.repo.calls.last, 'requestRegistrationOtp:$_e164:resend');

    await tester.enterText(find.byType(TextField), '909090');
    await tester.pumpAndSettle();

    expect(harness.account.calls, ['saveMobileNumber:$_e164:909090']);
    expect(find.byType(VerifyCodeScreen), findsNothing);
    expect(find.text('Mobile number updated'), findsOneWidget);
    await _drainCountdown(tester);
  });
}
