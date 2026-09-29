import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_providers.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_style.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/search_fixtures.dart';

/// Renders the Algolia search screens — type-ahead (Figma 09 / AR 48:1568),
/// results (09c / AR 67:2663) and no results (S2 / AR 54:2354) — in English
/// and Arabic to `build/test_screens/` for comparison with the frames. Each
/// render also fails on any layout exception, so it doubles as an RTL and
/// overflow check.
///
/// Tests can't load network images, so the records go without theirs and the
/// thumbnails show their placeholders.
AlgoliaAnswer _withoutImages(AlgoliaAnswer answer) => (query) {
  final result = answer(query);
  for (final hit in (result['hits'] as List).cast<Map<String, dynamic>>()) {
    hit
      ..remove('image_url')
      ..remove('thumbnail_url');
  }
  return result;
};

Widget _harness(
  GlobalKey boundary,
  FakeAlgoliaBackend algolia, {
  required String locale,
  String? initialQuery,
}) {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder: (_, __) => SearchScreen(initialQuery: initialQuery),
      ),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(
          categories: locale == 'ar' ? kSearchTreeAr : kSearchTree,
        ),
      ),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.unavailable()),
      algoliaHttpClientProvider.overrideWithValue(algolia.client),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
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
  addTearDown(tester.view.reset);
}

Future<void> _typeAhead(WidgetTester tester, String locale) async {
  _phone(tester);
  final key = GlobalKey();
  await tester.pumpWidget(
    _harness(
      key,
      FakeAlgoliaBackend(answer: _withoutImages(sofaAnswers(store: locale))),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextField),
    locale == 'ar' ? 'كنبة' : 'sofa',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  // The capture is of the list, not of a blinking caret.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await captureScreen(tester, key, 'search_09_typeahead_$locale');
}

Future<void> _results(WidgetTester tester, String locale) async {
  _phone(tester);
  final key = GlobalKey();
  await tester.pumpWidget(
    _harness(
      key,
      FakeAlgoliaBackend(answer: _withoutImages(sofaAnswers(store: locale))),
      locale: locale,
      initialQuery: locale == 'ar' ? 'كنبة' : 'sofa',
    ),
  );
  await tester.pumpAndSettle();
  await captureScreen(tester, key, 'search_09c_results_$locale');
}

Future<void> _noResults(WidgetTester tester, String locale) async {
  _phone(tester);
  final key = GlobalKey();
  await tester.pumpWidget(
    _harness(
      key,
      FakeAlgoliaBackend(
        answer: sofaAnswers(store: locale, products: false, suggestions: false),
      ),
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextField),
    locale == 'ar' ? 'كنبة سرير مخمل أخضر' : 'sofa bed velvet green',
  );
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await captureScreen(tester, key, 'search_S2_no_results_$locale');
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('type-ahead (09) renders in $locale', (tester) async {
      await withRealShadows(() => _typeAhead(tester, locale));
      expect(find.byType(SearchByAlgolia), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('results (09c) render in $locale', (tester) async {
      await withRealShadows(() => _results(tester, locale));
      expect(
        find.text(locale == 'ar' ? 'المنتجات (12)' : 'Products (12)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no results (S2) renders in $locale', (tester) async {
      await withRealShadows(() => _noResults(tester, locale));
      expect(tester.takeException(), isNull);
    });
  }
}
