import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_widgets.dart';

import 'auth_harness.dart';

const _typed = '050 123 4567';

Future<AuthHarness> _openSignInFrom(WidgetTester tester, String from) async {
  useTallView(tester);
  final harness = AuthHarness();
  await tester.pumpWidget(harness.build(initialLocation: from));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(TextButton)); // "CALLER" / "WELCOME"
  await tester.pumpAndSettle();
  expect(find.byType(SignInScreen), findsOneWidget);
  return harness;
}

Future<void> _signInByPassword(WidgetTester tester) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
  await tester.enterText(fields.at(1), 'Sara@2026x');
  await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
  await tester.pumpAndSettle();
}

/// Sign in returns to what opened it — guest checkout's "Sign in" must land
/// back on checkout — and only the flow started at Welcome goes Home.
void main() {
  testWidgets('a password sign-in returns to the caller with true', (
    tester,
  ) async {
    final harness = await _openSignInFrom(tester, callerRoute);
    await _signInByPassword(tester);

    expect(find.text('CALLER'), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    expect(harness.signInResults, [true]);
  });

  testWidgets('a sign-in by code closes Verify and Sign in, back to the caller',
      (tester) async {
    final harness = await _openSignInFrom(tester, callerRoute);
    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), _typed);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();
    expect(find.byType(VerifyCodeScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.pumpAndSettle();

    expect(find.text('CALLER'), findsOneWidget);
    expect(find.byType(VerifyCodeScreen), findsNothing);
    expect(harness.signInResults, [true]);
  });

  testWidgets('a sign-up started from Sign in also returns to the caller', (
    tester,
  ) async {
    final harness = await _openSignInFrom(tester, callerRoute);
    await tester.tap(find.text('Create account'));
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
    await tester.enterText(find.byType(TextField), '654321');
    await tester.pumpAndSettle();

    expect(find.text('CALLER'), findsOneWidget);
    expect(harness.signInResults, [true]);
  });

  testWidgets('from Welcome, a sign-in lands on Home', (tester) async {
    final harness = await _openSignInFrom(tester, AppRoutes.welcome);
    await _signInByPassword(tester);

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('WELCOME'), findsNothing);
    expect(harness.location, AppRoutes.home);
  });

  testWidgets('with nothing under it (a cold start), a sign-in lands on Home', (
    tester,
  ) async {
    final harness = AuthHarness();
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
    await tester.pumpAndSettle();
    await _signInByPassword(tester);

    expect(find.text('HOME'), findsOneWidget);
  });
}
