import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/onboarding/presentation/launch_splash_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

/// Figma "01 Splash": the launch screen's look (captured for review against
/// the frame, English and Arabic) and what it does while it holds.
Widget _harness({
  String locale = 'en',
  String? token,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, __) => const LaunchSplashScreen(),
      ),
      for (final (path, label) in [
        (AppRoutes.welcome, 'WELCOME'),
        (AppRoutes.home, 'HOME'),
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Center(child: Text(label))),
        ),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.unavailable()),
      // What the splash warms while it holds; nothing leaves the test.
      categoryTreeProvider.overrideWith((ref) async => const []),
      homeCmsBlocksProvider.overrideWith((ref) async => const {}),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
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
      ),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('01 Splash, as the frame ($locale)', (tester) async {
      _phone(tester);
      final key = GlobalKey();
      await tester.pumpWidget(_harness(locale: locale, boundary: key));
      // The frame draws the bar 52 / 120 of the way: 1.127 s into the hold.
      await tester.pump(const Duration(milliseconds: 1127));
      await captureScreen(tester, key, 'audit_01_splash_$locale');

      final l10n = AppLocalizations.of(
        tester.element(find.byType(LaunchSplashScreen)),
      );
      expect(find.text(l10n.launchTagline), findsOneWidget);
      // The frame's footer ("Across all seven emirates") is a claim the app
      // does not make (QA02).
      expect(find.textContaining('seven emirates'), findsNothing);
      expect(tester.takeException(), isNull);

      // Leave through the hold so no timer outlives the test.
      await tester.pump(LaunchSplashScreen.hold);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('holds for 2.6 s, then goes to Welcome without a session', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_harness());
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(LaunchSplashScreen), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('WELCOME'), findsOneWidget);
  });

  testWidgets('a saved session skips Welcome and lands on Home', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pump(LaunchSplashScreen.hold + const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('the progress bar counts the hold and ends full', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_harness());
    FractionallySizedBox fill() => tester.widget<FractionallySizedBox>(
      find.descendant(
        of: find.byType(LaunchSplashScreen),
        matching: find.byType(FractionallySizedBox),
      ),
    );
    expect(fill().widthFactor, 0);
    await tester.pump(LaunchSplashScreen.hold ~/ 2);
    expect(fill().widthFactor, closeTo(0.5, 0.01));
    await tester.pump(LaunchSplashScreen.hold ~/ 2);
    expect(fill().widthFactor, 1);
    await tester.pumpAndSettle();
  });
}
