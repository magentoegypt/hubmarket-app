import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/core/config/backend_capabilities.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_field.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import 'auth_harness.dart';

Future<void> _pumpBare(
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

Future<AuthHarness> _pump(WidgetTester tester, FakeAuthRepository repo) async {
  final harness = AuthHarness(repo: repo);
  await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signIn));
  await tester.pumpAndSettle();
  return harness;
}

bool _outlinedRed(WidgetTester tester, String label) => tester
    .widget<AuthField>(find.widgetWithText(AuthField, label))
    .showErrorBorder;

void main() {
  group('03 Sign in', () {
    testWidgets('opens on the Email tab with the WhatsApp-code shortcut', (
      tester,
    ) async {
      await _pumpBare(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Email address'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      expect(find.text('Continue with WhatsApp code'), findsOneWidget);
      expect(find.text('Send WhatsApp code'), findsNothing);
      // The store has no social sign-in, so the frame's row is not built.
      expect(find.text('Google'), findsNothing);
    });

    testWidgets('the Mobile tab swaps in the number and "Send WhatsApp code"', (
      tester,
    ) async {
      await _pumpBare(tester);
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();

      expect(find.text('Mobile number (WhatsApp)'), findsOneWidget);
      expect(find.text('Send WhatsApp code'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
    });

    testWidgets('without a token-issuing code endpoint it is e-mail only', (
      tester,
    ) async {
      await _pumpBare(tester, capabilities: const BackendCapabilities());
      expect(find.text('Mobile'), findsNothing);
      expect(find.text('Continue with WhatsApp code'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    testWidgets('renders Arabic right-to-left', (tester) async {
      await _pumpBare(tester, locale: 'ar');
      expect(find.text('رقم الجوال'), findsOneWidget); // Mobile tab
      expect(find.text('مرحبًا بعودتك'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(SignInScreen))),
        TextDirection.rtl,
      );
    });
  });

  group('S6 errors stay on the form', () {
    testWidgets('a refused sign-in: banner under the title, both fields red',
        (tester) async {
      await _pump(tester, FakeAuthRepository(loginFails: true));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(1), 'Sara@2026x');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.byType(AuthErrorBanner), findsOneWidget);
      expect(find.text('Email or password is incorrect'), findsOneWidget);
      expect(
        find.text('Repeated failures lock sign-in for 10 minutes.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(_outlinedRed(tester, 'Email address'), isTrue);
      expect(_outlinedRed(tester, 'Password'), isTrue);

      // Editing releases the fields; the banner stays until the next try.
      await tester.enterText(fields.at(1), 'Sara@2026y');
      await tester.pump();
      expect(_outlinedRed(tester, 'Password'), isFalse);
      expect(find.byType(AuthErrorBanner), findsOneWidget);
    });

    testWidgets("each field's own check shows under it", (tester) async {
      final repo = FakeAuthRepository();
      await _pump(tester, repo);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sara.ahmed@gmail');
      await tester.enterText(fields.at(1), '123456');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Password must be at least 8 characters'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'nothing is sent');
    });

    testWidgets('no connection says so in the banner', (tester) async {
      final repo = FakeAuthRepository()
        ..loginFailure = const Failure(FailureKind.network);
      await _pump(tester, repo);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(1), 'Sara@2026x');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "We couldn't reach the store. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(_outlinedRed(tester, 'Email address'), isFalse);
    });

    testWidgets('a number with no account is flagged under the mobile field', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..sendOtpFailure = const Failure(
          FailureKind.server,
          detail: 'Mobile number not found.',
        );
      await _pump(tester, repo);
      await tester.tap(find.text('Mobile'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0501234567');
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();

      expect(find.text('No account uses this mobile number.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);

      // Too many requests read differently.
      repo.sendOtpFailure = const Failure(
        FailureKind.server,
        detail: 'Please wait 30 seconds before requesting another code.',
      );
      await tester.tap(find.text('Send WhatsApp code'));
      await tester.pumpAndSettle();
      expect(
        find.text('Too many attempts. Wait a few minutes and try again.'),
        findsOneWidget,
      );
    });
  });

  group('04 Register errors', () {
    Future<FakeAuthRepository> fill(
      WidgetTester tester, {
      FakeAuthRepository? repo,
      bool terms = true,
      String password = 'Sara@2026x',
    }) async {
      useTallView(tester);
      final r = repo ?? FakeAuthRepository();
      final harness = AuthHarness(repo: r);
      await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signUp));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Sara');
      await tester.enterText(fields.at(1), 'Ahmed');
      await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(3), '0501234567');
      await tester.enterText(fields.at(4), password);
      if (terms) await tester.tap(find.byType(AuthCheckRow).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      return r;
    }

    testWidgets('the terms must be accepted', (tester) async {
      final repo = await fill(tester, terms: false);
      expect(find.text('Accept the terms to create your account.'),
          findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('a password short of the rule turns the rule line red', (
      tester,
    ) async {
      final repo = await fill(tester, password: 'sarapassword');
      final rule = tester.widget<AuthHelperLine>(
        find.widgetWithText(
          AuthHelperLine,
          '8+ characters, one number, one symbol',
        ),
      );
      expect(rule.color, AppColors.danger);
      expect(
        tester
            .widget<AuthField>(find.widgetWithText(AuthField, 'Password'))
            .validator!('sarapassword'),
        '',
        reason: 'red outline, the rule line says why',
      );
      expect(repo.calls, isEmpty);
    });

    testWidgets('a number already in use is flagged under the mobile field', (
      tester,
    ) async {
      await fill(
        tester,
        repo: FakeAuthRepository()
          ..sendOtpFailure = const Failure(
            FailureKind.server,
            detail: 'The mobile number is used by another customer account.',
          ),
      );
      expect(
        find.text('Another account already uses this mobile number.'),
        findsOneWidget,
      );
    });

    testWidgets('an e-mail already in use is flagged under the e-mail field', (
      tester,
    ) async {
      final repo = FakeAuthRepository()
        ..registerFailure = const Failure(
          FailureKind.server,
          detail:
              'A customer with the same email address already exists in an '
              'associated website.',
        );
      await fill(tester, repo: repo);
      await tester.enterText(find.byType(TextField), '123456'); // on Verify
      await tester.pumpAndSettle();

      expect(find.text('An account with this email already exists.'),
          findsOneWidget);
      expect(find.text('HOME'), findsNothing);
    });
  });
}
