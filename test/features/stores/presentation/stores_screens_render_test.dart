import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/stores/presentation/widgets/search_vendor_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';
import '../stores_harness.dart';

/// Renders the stores screens — 12 Stores (AR 50:1745), 13 Store page
/// (AR 24:247), 13b About (AR 96:3475) — and the search pages they add to,
/// 09c results with Vendors (AR 67:2663) and S2 no results (AR 54:2354), in
/// English and Arabic to `build/test_screens/` for comparison with the
/// frames. Each render also fails on any layout exception, so it doubles as
/// an RTL and overflow check.
///
/// Tests can't load network images: logos show their initials, banners the
/// brand navy and product cards their placeholders.
void _surface(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Algolia's answers for the search renders; the seller facet names MIA CO
/// in the store view's language, as the index does.
AlgoliaAnswer _algolia(String locale, {bool products = true}) => (query) {
  final result = sofaAnswers(
    store: locale,
    products: products,
    suggestions: products,
  )(query);
  final facets = result['facets'];
  if (facets is Map<String, dynamic>) {
    result['facets'] = {
      ...facets,
      'seller': {locale == 'ar' ? 'ميا كو' : 'MIA CO': 8},
    };
  }
  for (final hit in (result['hits'] as List).cast<Map<String, dynamic>>()) {
    hit
      ..remove('image_url')
      ..remove('thumbnail_url');
  }
  return result;
};

Widget _searchHarness(
  GlobalKey boundary, {
  required String locale,
  required FakeAlgoliaBackend algolia,
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
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
      publicGraphqlClientProvider.overrideWithValue(
        FakeStoresBackend(storesAnswers(store: locale)).client,
      ),
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

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('12 Stores renders in $locale', (tester) async {
      await withRealShadows(() async {
        _surface(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          storesHarness(
            location: '/stores',
            backend: FakeStoresBackend(storesAnswers(store: locale)),
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'stores_12_list_$locale');
      });
      expect(
        find.text(locale == 'ar' ? 'كل المتاجر' : 'All stores'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('13 Store page renders in $locale', (tester) async {
      await withRealShadows(() async {
        _surface(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          storesHarness(
            location: '/store/MIA',
            backend: FakeStoresBackend(storesAnswers(store: locale)),
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'stores_13_store_$locale');
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('13b About renders in $locale', (tester) async {
      await withRealShadows(() async {
        _surface(tester, height: 1075);
        final key = GlobalKey();
        await tester.pumpWidget(
          storesHarness(
            location: '/store/MIA',
            backend: FakeStoresBackend(storesAnswers(store: locale)),
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(locale == 'ar' ? 'عن المتجر' : 'About'));
        await tester.pumpAndSettle();
        // Scrolled as in the frame: the header collapsed, the tabs pinned.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -330));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'stores_13b_about_$locale');
      });
      expect(tester.takeException(), isNull);
    });

    testWidgets('09c results with Vendors render in $locale', (tester) async {
      await withRealShadows(() async {
        _surface(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          _searchHarness(
            key,
            locale: locale,
            algolia: FakeAlgoliaBackend(answer: _algolia(locale)),
            initialQuery: locale == 'ar' ? 'كنبة' : 'sofa',
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'search_09c_vendors_$locale');
      });
      expect(find.byType(SearchVendorCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('S2 with Popular right now renders in $locale', (tester) async {
      await withRealShadows(() async {
        _surface(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          _searchHarness(
            key,
            locale: locale,
            algolia: FakeAlgoliaBackend(
              answer: _algolia(locale, products: false),
            ),
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
        await captureScreen(tester, key, 'search_S2_stores_$locale');
      });
      expect(
        find.text(locale == 'ar' ? 'تصفّح المتاجر' : 'Browse stores'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
