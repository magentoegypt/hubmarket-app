import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/widgets/country_picker_sheet.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_widgets.dart';

import 'auth_harness.dart';

// QA TC99: "the phone number field across all pages ... accepts only UAE phone
// numbers and does not provide a country selector". Every flow that sends a code
// takes a number of any country now: the chip on the field says which, and the
// store gets the number in E.164.

/// A mobile of Egypt: typed without the trunk 0, as the chip's country needs it.
const _egyptTyped = '100 123 4567';
const _egyptE164 = '+201001234567';

final _chip = find.byKey(const ValueKey('phone-country-chip'));

/// Opens the list from the chip, searches for [name] as a shopper would and
/// taps it.
Future<void> _pickCountry(WidgetTester tester, String name) async {
  await tester.tap(_chip);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(CountryPickerSheet),
      matching: find.byType(TextField),
    ),
    name,
  );
  await tester.pumpAndSettle();
  // The row, not the search box that now holds the same words.
  await tester.tap(find.widgetWithText(InkWell, name).first);
  await tester.pumpAndSettle();
}

void main() {
  group('sign in by code', () {
    testWidgets('a number of another country, picked from the list: its E.164 '
        'is what the store is sent', (tester) async {
      useTallView(tester);
      final harness = AuthHarness();
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();

      await _pickCountry(tester, 'Egypt');
      expect(find.text('+20'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '0100 123 4567');
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyCodeScreen), findsOneWidget);
      expect(harness.repo.calls, ['requestLoginOtp:$_egyptE164']);
    });

    testWidgets('a number typed with its country code sets the chip itself', (
      tester,
    ) async {
      useTallView(tester);
      final harness = AuthHarness();
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '+20 100 123 4567');
      await tester.pumpAndSettle();
      expect(find.text('+20'), findsOneWidget);
      expect(find.text('+971'), findsNothing);

      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();
      expect(harness.repo.calls, ['requestLoginOtp:$_egyptE164']);
    });

    testWidgets('a number that is not one of the country on the chip is '
        'refused, naming the country, and nothing is sent', (tester) async {
      useTallView(tester);
      final harness = AuthHarness();
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();

      // An Egyptian number on the UAE chip.
      await tester.enterText(find.byType(TextField), _egyptTyped);
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a valid mobile number for United Arab Emirates'),
        findsOneWidget,
      );
      expect(harness.repo.calls, isEmpty);
      expect(find.byType(VerifyCodeScreen), findsNothing);

      // The right chip makes it a number.
      await _pickCountry(tester, 'Egypt');
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();
      expect(harness.repo.calls, ['requestLoginOtp:$_egyptE164']);
    });

    testWidgets('a landline is refused: a code does not reach it', (
      tester,
    ) async {
      useTallView(tester);
      final harness = AuthHarness();
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      await _pickCountry(tester, 'Egypt');

      // A Cairo landline.
      await tester.enterText(find.byType(TextField), '02 21234567');
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid mobile number for Egypt'), findsOneWidget);
      expect(harness.repo.calls, isEmpty);
    });

    testWidgets('speaks Arabic in Arabic, with the country\'s name', (
      tester,
    ) async {
      useTallView(tester);
      final harness = AuthHarness(locale: 'ar');
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
      await tester.pumpAndSettle();
      await tester.tap(find.text('رقم الجوال'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '123');
      await tester.tap(find.text('إرسال رمز عبر واتساب'));
      await tester.pumpAndSettle();

      expect(
        find.text('أدخل رقم جوال صحيحًا لدولة الإمارات العربية المتحدة'),
        findsOneWidget,
      );
    });
  });

  testWidgets('register with a Saudi number: the code goes to it and the '
      'account is made with it', (tester) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signUp));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Sara');
    await tester.enterText(fields.at(1), 'Ahmed');
    await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
    await _pickCountry(tester, 'Saudi Arabia');
    await tester.enterText(fields.at(3), '050 123 4567');
    await tester.enterText(fields.at(4), 'Sara@2026x');
    await tester.tap(find.byType(AuthCheckRow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyCodeScreen), findsOneWidget);
    expect(harness.repo.calls, ['requestRegistrationOtp:+966501234567']);
    await tester.enterText(find.byType(TextField), '654321');
    await tester.pumpAndSettle();
    expect(harness.repo.calls.sublist(1), [
      'verifyRegistrationOtp:+966501234567:654321',
      'register:sara.ahmed@gmail.com:+966501234567',
      'login:sara.ahmed@gmail.com',
    ]);
  });

  testWidgets('forgot password by code for an Indian number', (tester) async {
    useTallView(tester);
    final harness = AuthHarness();
    await tester.pumpWidget(
      harness.build(initialLocation: AppRoutes.forgotPassword),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mobile'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '+91 98765 43210');
    await tester.pumpAndSettle();
    expect(find.text('+91'), findsOneWidget);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();

    expect(harness.repo.calls, ['requestPasswordResetOtp:+919876543210']);
  });

  testWidgets('change mobile to a number of another country', (tester) async {
    useTallView(tester);
    final harness = AuthHarness(signedIn: true);
    await tester.pumpWidget(harness.build(initialLocation: editMobileRoute));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await _pickCountry(tester, 'Egypt');
    await tester.enterText(find.byType(TextField), _egyptTyped);
    await tester.tap(find.text('Send WhatsApp code'));
    await tester.pumpAndSettle();

    expect(find.byType(VerifyCodeScreen), findsOneWidget);
    expect(harness.repo.calls, ['requestRegistrationOtp:$_egyptE164']);
    await tester.pump(const Duration(seconds: 61));
  });
}
