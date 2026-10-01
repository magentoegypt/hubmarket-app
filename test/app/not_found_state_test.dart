import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/not_found_state.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../support/fakes.dart';
import '../support/fonts.dart';

/// Figma "S7 Page not found": the page, over Home as it is reached from a link.
const String _missing = '/missing';

GoRouter _router() => GoRouter(
  initialLocation: AppRoutes.home,
  routes: [
    GoRoute(path: AppRoutes.home, builder: (_, __) => const Text('HOME')),
    GoRoute(path: AppRoutes.search, builder: (_, __) => const Text('SEARCH')),
    GoRoute(path: _missing, builder: (_, __) => const NotFoundPage()),
    for (final p in [
      AppRoutes.categories,
      AppRoutes.cart,
      AppRoutes.wishlist,
      AppRoutes.account,
    ])
      GoRoute(path: p, builder: (_, __) => const Text('TAB')),
  ],
);

Widget _app(GoRouter router, String locale, {GlobalKey? boundary}) {
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
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
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
    testWidgets('S7 as the frame ($locale)', (tester) async {
      _phone(tester);
      final key = GlobalKey();
      final router = _router();
      await tester.pumpWidget(_app(router, locale, boundary: key));
      await tester.pumpAndSettle();
      unawaited(router.push(_missing));
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'audit_S7_not_found_$locale');

      final l10n = AppLocalizations.of(tester.element(find.byType(NotFoundPage)));
      expect(find.text(l10n.notFoundTitle), findsOneWidget);
      expect(find.text(l10n.notFoundBody), findsOneWidget);
      expect(find.text(l10n.notFoundSearch), findsOneWidget);
      expect(find.text(l10n.notFoundHome), findsOneWidget);
      // The back arrow (a pushed page) and the tab bar are the page's chrome.
      expect(find.byIcon(HubIcons.arrowLeft), findsOneWidget);
      expect(find.text(l10n.navHome), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the disc is the frame\'s amber with an orange search glyph', (
    tester,
  ) async {
    _phone(tester);
    final router = _router();
    await tester.pumpWidget(_app(router, 'en'));
    await tester.pumpAndSettle();
    unawaited(router.push(_missing));
    await tester.pumpAndSettle();

    final disc = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(HubIcons.search),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((disc.decoration! as BoxDecoration).color, AppColors.warningSubtle);
    expect(tester.getSize(find.byWidget(disc)), const Size(112, 112));
    final glyph = tester.widget<Icon>(find.byIcon(HubIcons.search));
    expect(glyph.size, 48);
    expect(glyph.color, AppColors.accentStrong);
  });

  testWidgets('Search Hub Market opens the search, Go to Home goes Home', (
    tester,
  ) async {
    _phone(tester);
    final router = _router();
    await tester.pumpWidget(_app(router, 'en'));
    await tester.pumpAndSettle();
    unawaited(router.push(_missing));
    await tester.pumpAndSettle();

    String where() =>
        router.routerDelegate.currentConfiguration.last.matchedLocation;

    await tester.tap(find.text('Search Hub Market'));
    await tester.pumpAndSettle();
    expect(where(), AppRoutes.search);
    router.pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Go to Home'));
    await tester.pumpAndSettle();
    expect(where(), AppRoutes.home);
  });

  testWidgets('a screen can say it in its own words', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => const Scaffold(
                body: NotFoundState(
                  title: 'Store not found',
                  body: 'This store isn\'t on Hub Market right now.',
                ),
              ),
            ),
          ],
        ),
        'en',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Store not found'), findsOneWidget);
    expect(find.text('This store isn\'t on Hub Market right now.'), findsOneWidget);
    // The ways on stay the same.
    expect(find.text('Search Hub Market'), findsOneWidget);
    expect(find.text('Go to Home'), findsOneWidget);
  });
}
