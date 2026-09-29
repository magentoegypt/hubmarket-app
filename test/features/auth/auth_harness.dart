import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/mobile_number_editor.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/domain/password_reset_ticket.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/reset_password_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

/// Route of the stub that hosts the Edit-Profile mobile editor.
const String editMobileRoute = '/edit-mobile';

/// The auth screens on their real routes (sign in, register, forgot, verify,
/// reset) over fakes, with stub Home / Edit-Profile hosts — so a test can walk
/// a whole flow: form → "05 Verify WhatsApp code" → where it lands.
class AuthHarness {
  AuthHarness({
    this.locale = 'en',
    FakeAuthRepository? repo,
    FakeAccountRepository? account,
    this.signedIn = false,
  }) : repo = repo ?? FakeAuthRepository(),
       account = account ?? FakeAccountRepository();

  final String locale;
  final FakeAuthRepository repo;
  final FakeAccountRepository account;
  final bool signedIn;
  late final GoRouter router;

  Widget build({
    required String initialLocation,
    Object? initialExtra,
    GlobalKey? boundary,
  }) {
    router = GoRouter(
      initialLocation: initialLocation,
      initialExtra: initialExtra,
      routes: [
        GoRoute(
          path: AppRoutes.home,
          builder: (_, _) => const Scaffold(body: Center(child: Text('HOME'))),
        ),
        GoRoute(
          path: AppRoutes.signIn,
          builder: (_, _) => const SignInScreen(),
        ),
        GoRoute(
          path: AppRoutes.signUp,
          builder: (_, _) => const SignUpScreen(),
        ),
        GoRoute(
          path: AppRoutes.forgotPassword,
          builder: (_, _) => const ForgotPasswordScreen(),
        ),
        GoRoute(
          path: AppRoutes.resetPassword,
          builder: (_, state) => state.extra is PasswordResetTicket
              ? ResetPasswordScreen.fromTicket(
                  state.extra! as PasswordResetTicket,
                )
              : const ResetPasswordScreen(),
        ),
        GoRoute(
          path: AppRoutes.verifyCode,
          builder: (_, state) =>
              VerifyCodeScreen(flow: state.extra! as VerifyCodeFlow),
        ),
        GoRoute(
          path: editMobileRoute,
          builder: (_, _) => const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: MobileNumberEditor(),
            ),
          ),
        ),
      ],
    );
    final app = MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: AppTheme.light(locale),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
    return ProviderScope(
      overrides: [
        secureTokenStoreProvider.overrideWithValue(
          FakeSecureTokenStore(signedIn ? 'persisted' : null),
        ),
        authRepositoryProvider.overrideWithValue(repo),
        accountRepositoryProvider.overrideWithValue(account),
      ],
      child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
    );
  }

  String get location => router.routerDelegate.currentConfiguration.uri.path;
}

/// Only the change-mobile call the Verify screen makes through the account
/// feature; everything else is unused by these tests.
class FakeAccountRepository extends Fake implements AccountRepository {
  final List<String> calls = [];
  Object? saveFailure;

  @override
  Future<void> saveMobileNumber(String mobileNumber, String code) async {
    calls.add('saveMobileNumber:$mobileNumber:$code');
    if (saveFailure != null) throw saveFailure!;
  }
}

/// A view tall enough for the longest form (Register) to fit without
/// scrolling, so every control can be tapped where it is.
void useTallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A phone-sized view (390×844) with the status-bar and home-indicator insets
/// of the Figma frames, so captures line up with them.
void usePhoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}
