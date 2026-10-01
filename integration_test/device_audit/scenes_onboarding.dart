import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/not_found_state.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/network/connectivity.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/validation/password_policy.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_in_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/sign_up_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/screens/verify_code_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_widgets.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/features/cms/domain/cms_links.dart';
import 'package:hubmarket_app/features/cms/presentation/cms_providers.dart';
import 'package:hubmarket_app/features/account/presentation/screens/orders_screen.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/features/onboarding/presentation/launch_splash_screen.dart';
import 'package:hubmarket_app/features/onboarding/presentation/welcome_screen.dart';

import '../../test/support/fakes.dart';
import '../../test/support/hubapp_fakes.dart';
import 'audit_scene.dart';
import 'harness.dart';
import 'onboarding_fixtures.dart';

/// Onboarding and auth, and the app-wide states: A01 Splash, A01a Launch, A02 Welcome, A03 Sign in, A04 Register, A05 Verify code, A06 Forgot password; F_S3 Offline, F_S4 Loading (home / cart / orders skeletons), F_S6 Sign-in errors, F_S7 Not found.
///
/// One scene per frame state, ported from the widget test that renders it (see
/// docs/ui-audit.md, `PAIRS` in tool/ui_audit/pairs.py names the captures):
///
/// * A01  test/features/onboarding/launch_splash_screen_test.dart
/// * A02  test/features/onboarding/welcome_screen_test.dart
/// * A03-A06, S6  test/features/auth/auth_screens_render_test.dart
/// * S3   test/core/widgets/offline_state_test.dart ("S3 render")
/// * S4   test/features/home/home_skeleton_test.dart,
///        test/features/cart/cart_screen_states_test.dart,
///        test/features/account/account_lists_states_test.dart
/// * S7   test/app/not_found_state_test.dart
///
/// A01a (the launch screen) has no scene: it is the *native* one (an Android
/// drawable and an iOS storyboard, drawn by the OS before Flutter starts), and
/// no Flutter widget draws it — `LaunchSplashScreen` is A01.
List<AuditScene> scenes() => [
  // ---- A01 Splash ---------------------------------------------------------
  // The frame draws the bar 52 / 120 of the way: 1.127 s into the 2.6 s hold.
  // The splash then leaves for Welcome, and its hold is a Future.delayed that
  // nothing can cancel (the host sweep fails on a timer left pending), so the
  // scene lets the hold run out *after* freezing the animation at 1.127 s: the
  // token read never answers (nothing to route on) and the capture still shows
  // the bar where the frame has it.
  AuditScene(
    frame: 'A01_splash',
    name: 'default',
    pushed: false,
    signedIn: false,
    settleMs: 0,
    screen: (_) => const FrozenTickers(child: LaunchSplashScreen()),
    setup: (_) => AuditSetup(
      hubApp: const HubAppState.unavailable(),
      overrides: [
        offlinePublicClient(),
        secureTokenStoreProvider.overrideWithValue(HoldingTokenStore()),
        // What the splash warms while it holds; nothing leaves the app.
        categoryTreeProvider.overrideWith((ref) async => const []),
        homeCmsBlocksProvider.overrideWith((ref) async => const {}),
      ],
    ),
    act: (tester, locale) async {
      await pumpFor(tester, 1127);
      tester.state<FrozenTickersState>(find.byType(FrozenTickers)).freeze();
      await tester.pump();
      await pumpFor(tester, LaunchSplashScreen.hold.inMilliseconds + 100);
    },
  ),

  // ---- A02 Welcome --------------------------------------------------------
  // Without slides (Build 1): the logo panel, with the store's delivery
  // promise as its pill.
  AuditScene(
    frame: 'A02_welcome',
    name: 'logo_panel',
    pushed: false,
    signedIn: false,
    screen: (_) => const WelcomeScreen(),
    setup: (locale) => AuditSetup(
      hubApp: const HubAppState.unavailable(),
      overrides: [
        offlinePublicClient(),
        welcomeSlidesProvider.overrideWith(
          (ref) async => const <HmHeroBanner>[],
        ),
        homeCmsBlocksProvider.overrideWith(
          (ref) async => deliveryPromiseBlock(locale),
        ),
      ],
    ),
  ),
  // With the Hero Banner slides: the photo carousel with its kicker pills and
  // the pager.
  AuditScene(
    frame: 'A02_welcome',
    name: 'slides',
    pushed: false,
    signedIn: false,
    screen: (_) => const WelcomeScreen(),
    setup: (locale) => AuditSetup(
      hubApp: const HubAppState.available(kSampleHmAppConfig),
      overrides: [
        offlinePublicClient(),
        welcomeSlidesProvider.overrideWith((ref) async => welcomeSlides(locale)),
      ],
    ),
  ),

  // ---- A03 - A06 and S6: the auth screens ---------------------------------
  // Each is a root here (the test opens the route directly), signed out, with
  // the live store's password rules and no legal links (so the terms row is
  // plain text), as test/features/auth/auth_harness.dart sets them.
  AuditScene(
    frame: 'A03_sign_in',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const SignInScreen(),
    setup: (_) => _authSetup(),
    act: (tester, locale) async {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(1), 'Sara@2026x');
      await pumpFor(tester, 400);
    },
  ),
  AuditScene(
    frame: 'A04_register',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const SignUpScreen(),
    setup: (_) => _authSetup(),
    act: (tester, locale) async {
      final fields = find.byType(TextField);
      final ar = locale == 'ar';
      await tester.enterText(fields.at(0), ar ? 'سارة' : 'Sara');
      await tester.enterText(fields.at(1), ar ? 'أحمد' : 'Ahmed');
      await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(3), '+971 50 123 4567');
      await tester.enterText(fields.at(4), 'Sara@2026x');
      // Terms ticked, offers left off (Figma 04).
      await tester.tap(find.byType(AuthCheckRow).first);
      await pumpFor(tester, 400);
    },
  ),
  // Figma 05: four digits typed and 18 s of the 60 s resend cooldown gone
  // ("00:42"). The countdown starts at 43 s here instead, so the capture, taken
  // about a second and a half in, reads the frame's 00:42 without waiting.
  AuditScene(
    frame: 'A05_verify',
    name: 'default',
    pushed: false,
    signedIn: false,
    settleMs: 500,
    screen: (_) => VerifyCodeScreen(flow: _verifyFlow(resendAfterSeconds: 43)),
    setup: (_) => _authSetup(),
    act: (tester, locale) async {
      await tester.enterText(find.byType(TextField), '4821');
      await pumpFor(tester, 300);
    },
  ),
  AuditScene(
    frame: 'A06_forgot',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const ForgotPasswordScreen(),
    setup: (_) => _authSetup(),
    act: (tester, locale) async {
      await tester.enterText(find.byType(TextField), 'sara.ahmed@gmail.com');
      await pumpFor(tester, 400);
    },
  ),
  // S6: a refused sign-in first (the banner under the title), then what S6
  // shows under the fields: a malformed e-mail and a short password.
  AuditScene(
    frame: 'F_S6_signin_errors',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const SignInScreen(),
    setup: (_) => _authSetup(repo: FakeAuthRepository(loginFails: true)),
    act: (tester, locale) async {
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'sara.ahmed@gmail.com');
      await tester.enterText(fields.at(1), 'Sara@2026x');
      await tester.tap(find.byType(FilledButton));
      await pumpFor(tester, 500);
      await tester.enterText(fields.at(0), 'sara.ahmed@gmail');
      await tester.enterText(fields.at(1), '123456');
      await tester.tap(find.byType(FilledButton));
      await pumpFor(tester, 500);
    },
  ),

  // ---- S3 Offline ---------------------------------------------------------
  // The product list pushed over Home, its request never reaching the store,
  // and the OS reporting no network: the "You're offline" page, with the strip
  // docked above the tab bar (the screen's own slot; the app-wide host that
  // draws it on screens without tabs is not part of the audit app shell).
  AuditScene(
    frame: 'F_S3_offline',
    name: 'default',
    signedIn: false,
    screen: (locale) => PlpScreen(
      categoryUid: 'cat-furniture',
      title: locale == 'ar' ? 'أثاث منزلي' : 'Home Furniture',
    ),
    setup: (_) => AuditSetup(
      overrides: [
        networkStatusSourceProvider.overrideWithValue(
          () => Stream<bool>.value(false),
        ),
        catalogRepositoryProvider.overrideWithValue(OfflineCatalogRepository()),
      ],
    ),
  ),

  // ---- S4 Loading ---------------------------------------------------------
  // Home while its content is still out: the frame's resting skeleton (no
  // sweep over it).
  AuditScene(
    frame: 'F_S4_loading',
    name: 'home_loading',
    pushed: false,
    signedIn: false,
    screen: (_) => const ReduceMotion(child: HubHomeScreen()),
    setup: (_) => AuditSetup(
      overrides: [
        offlinePublicClient(),
        hubAppProvider.overrideWith(PendingHubAppProbe.new),
      ],
    ),
  ),
  // The cart tab of a guest with a cart on the device, whose first load has
  // not answered.
  AuditScene(
    frame: 'F_S4_loading',
    name: 'cart_loading',
    pushed: false,
    signedIn: false,
    screen: (_) => const CartScreen(),
    setup: (_) => AuditSetup(
      hubApp: const HubAppState.unavailable(),
      overrides: [
        offlinePublicClient(),
        localCacheProvider.overrideWithValue(
          FakeLocalCache()..writeString('guest_cart_id', 'guest-1'),
        ),
        cartRepositoryProvider.overrideWithValue(SlowCartRepository()),
        freeShippingThresholdProvider.overrideWith((ref) async => null),
      ],
    ),
  ),
  // My orders on its first load: three order-card skeletons.
  AuditScene(
    frame: 'F_S4_loading',
    name: 'orders_loading',
    pushed: false,
    screen: (_) => const OrdersScreen(),
    setup: (_) => AuditSetup(
      account: SlowOrdersRepository(),
      hubApp: const HubAppState.unavailable(),
    ),
  ),

  // ---- S7 Page not found --------------------------------------------------
  // Pushed over Home, as it is reached from a link; the page, with the tab bar
  // and Home lit.
  AuditScene(
    frame: 'F_S7_not_found',
    name: 'default',
    signedIn: false,
    screen: (_) => const NotFoundPage(),
  ),
];

/// What the auth screens run with (test/features/auth/auth_harness.dart): the
/// live store's password rules (8 characters, 3 character classes), no legal
/// links, and [repo] for the e-mail / code calls.
AuditSetup _authSetup({FakeAuthRepository? repo}) => AuditSetup(
  features: const StoreFeatures(
    passwordPolicy: PasswordPolicy(minLength: 8, requiredClasses: 3),
  ),
  overrides: [
    if (repo != null) authRepositoryProvider.overrideWithValue(repo),
    legalLinksProvider.overrideWith((ref) async => linksFromHtml('')),
  ],
);

/// A code sent to +971 50 123 4567 that the store accepts: the Verify screen
/// of the sign-in-by-WhatsApp flow, with "Use email instead".
VerifyCodeFlow _verifyFlow({required int resendAfterSeconds}) => VerifyCodeFlow(
  phone: '+971501234567',
  offerEmail: true,
  resendAfterSeconds: resendAfterSeconds,
  resend: () async {},
  verify: (_) async => null,
);
