import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/backend_capabilities.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/otp_code_field.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

Future<void> _pump(
  WidgetTester tester, {
  String locale = 'en',
  BackendCapabilities capabilities = BackendCapabilities.hubMarket,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        backendCapabilitiesProvider.overrideWithValue(capabilities),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const SignInScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('defaults to the Email tab (password sign-in)', (tester) async {
    await _pump(tester);
    expect(find.text('Sign In'), findsOneWidget); // email submit button
    expect(find.text('Get OTP'), findsNothing);
  });

  testWidgets('switching to Phone reveals the phone field + Get OTP',
      (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Phone Number'));
    await tester.pumpAndSettle();

    expect(find.text('Get OTP'), findsOneWidget);
    expect(find.text('+971'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing); // email button is gone
  });

  testWidgets('Get OTP transitions to the 6-box verify state', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Phone Number'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), '501234567');
    await tester.tap(find.text('Get OTP'));
    await tester.pump(); // requestLoginOtp future + setState
    await tester.pump();

    expect(find.byType(OtpCodeField), findsOneWidget);
    expect(find.text('Verify & Sign In'), findsOneWidget);
    expect(find.text('Resend code'), findsNothing); // still counting down

    // Drain the 60s resend cooldown so no timer is pending at teardown.
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('without a token-issuing OTP endpoint there is no Phone tab', (
    tester,
  ) async {
    await _pump(tester, capabilities: const BackendCapabilities());
    expect(find.text('Phone Number'), findsNothing);
    expect(find.text('Sign In'), findsOneWidget); // e-mail + password only
  });

  testWidgets('renders Arabic tab labels + RTL', (tester) async {
    await _pump(tester, locale: 'ar');
    expect(find.text('رقم الهاتف'), findsOneWidget); // Phone Number tab
    expect(
      Directionality.of(tester.element(find.byType(SignInScreen))),
      TextDirection.rtl,
    );
  });
}
