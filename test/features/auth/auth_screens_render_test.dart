import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_widgets.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import 'auth_harness.dart';

/// Renders Figma 03 / 04 / 05 / 06 and S6 in English and Arabic with the
/// bundled fonts into `build/test_screens/` for side-by-side review with the
/// frames, and checks each lays out without overflow in both directions.
void main() {
  setUpAll(loadAppFonts);

  /// Pumps [location] in a 390×844 phone view, lets [act] fill it in, then
  /// captures `build/test_screens/<name>_<locale>.png`.
  Future<void> render(
    WidgetTester tester, {
    required String locale,
    required String name,
    required String location,
    Object? extra,
    FakeAuthRepository? repo,
    Future<void> Function()? act,
  }) => withRealShadows(() async {
    usePhoneView(tester);
    final key = GlobalKey();
    final harness = AuthHarness(locale: locale, repo: repo);
    await tester.pumpWidget(
      harness.build(
        initialLocation: location,
        initialExtra: extra,
        boundary: key,
      ),
    );
    await tester.pumpAndSettle();
    await act?.call();
    await captureScreen(tester, key, '${name}_$locale');
    expect(tester.takeException(), isNull);
    // Let a resend countdown run out so no timer outlives the test.
    await tester.pump(const Duration(seconds: 61));
  });

  VerifyCodeFlow flow({bool refuse = false}) => VerifyCodeFlow(
    phone: '+971501234567',
    offerEmail: true,
    resend: () async {},
    verify: (_) async {
      if (refuse) {
        throw const Failure(
          FailureKind.server,
          detail: 'The OTP code is not valid.',
        );
      }
      return null;
    },
  );

  for (final locale in ['en', 'ar']) {
    group('[$locale]', () {
      testWidgets('03 Sign in', (tester) async {
        await render(
          tester,
          locale: locale,
          name: '03_sign_in',
          location: AppRoutes.signIn,
          act: () async {
            final fields = find.byType(TextField);
            await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
            await tester.enterText(fields.at(1), 'Sara@2026x');
            await tester.pumpAndSettle();
          },
        );
      });

      testWidgets('S6 Sign-in errors', (tester) async {
        await render(
          tester,
          locale: locale,
          name: 'S6_sign_in_errors',
          location: AppRoutes.signIn,
          repo: FakeAuthRepository(loginFails: true),
          act: () async {
            final fields = find.byType(TextField);
            // A refused sign-in first (the banner), then what S6 shows under
            // the fields: a malformed e-mail and a short password.
            await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
            await tester.enterText(fields.at(1), 'Sara@2026x');
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
            await tester.enterText(fields.at(0), 'sara.ahmed@gmail');
            await tester.enterText(fields.at(1), '123456');
            await tester.tap(find.byType(FilledButton));
            await tester.pumpAndSettle();
          },
        );
      });

      testWidgets('04 Register', (tester) async {
        await render(
          tester,
          locale: locale,
          name: '04_register',
          location: AppRoutes.signUp,
          act: () async {
            final fields = find.byType(TextField);
            final ar = locale == 'ar';
            await tester.enterText(fields.at(0), ar ? 'سارة' : 'Sara');
            await tester.enterText(fields.at(1), ar ? 'أحمد' : 'Ahmed');
            await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
            await tester.enterText(fields.at(3), '+971 50 123 4567');
            await tester.enterText(fields.at(4), 'Sara@2026x');
            // Terms ticked, offers left off (Figma 04).
            await tester.tap(find.byType(AuthCheckRow).first);
            await tester.pumpAndSettle();
          },
        );
      });

      testWidgets('05 Verify WhatsApp code', (tester) async {
        await render(
          tester,
          locale: locale,
          name: '05_verify_code',
          location: AppRoutes.verifyCode,
          extra: flow(),
          act: () async {
            await tester.enterText(find.byType(TextField), '4821');
            await tester.pump(const Duration(seconds: 18)); // "00:42"
            await tester.pump();
          },
        );
      });

      testWidgets('05 with a refused code', (tester) async {
        await render(
          tester,
          locale: locale,
          name: '05_verify_code_error',
          location: AppRoutes.verifyCode,
          extra: flow(refuse: true),
          act: () async {
            await tester.enterText(find.byType(TextField), '482193');
            await tester.pumpAndSettle();
          },
        );
      });

      testWidgets('06 Forgot password', (tester) async {
        await render(
          tester,
          locale: locale,
          name: '06_forgot_password',
          location: AppRoutes.forgotPassword,
          act: () async {
            await tester.enterText(
              find.byType(TextField),
              'sara.ahmed@gmail.com',
            );
            await tester.pumpAndSettle();
          },
        );
      });
    });
  }
}
