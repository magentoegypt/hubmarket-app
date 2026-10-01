import 'dart:convert';

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
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/search_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_style.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';
import '../../stores/stores_harness.dart';

/// Renders the Algolia search screens — landing (Figma 09b / AR 67:2495),
/// type-ahead (09 / AR 48:1568), results (09c / AR 67:2663) and no results
/// (S2 / AR 54:2354) — in English and Arabic to `build/test_screens/` for
/// comparison with the frames. Each render also fails on any layout
/// exception, so it doubles as an RTL and overflow check.
///
/// The frames draw the Hub Market App's search (vendors, trending searches,
/// "Browse stores", "Popular right now"), so the captures named after them run
/// with it available; `*_plain` ones run without it, as Build 1 shows search.
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

/// [sofaAnswers] with the seller facet MIA CO (as the index names it in the
/// store view's language) and no images.
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

/// The Hub Market App as the frames show it: trending searches, and a server
/// that lists its satellites (sellers on cards, the store extras).
HubAppState _hubApp(String locale) => HubAppState.available(
  HmAppConfig(
    storeCode: locale,
    locale: locale == 'ar' ? 'ar_SA' : 'en_US',
    search: HmSearchConfig(
      trendingTerms: locale == 'ar'
          ? const [
              'حقيبة',
              'سامسونج',
              'قميص',
              'فستان',
              'كنبة',
              'أرز',
              'عطور',
              'حليب',
            ]
          : const [
              'bag',
              'Samsung',
              'shirt',
              'dress',
              'sofa',
              'rice',
              'perfume',
              'milk',
            ],
    ),
    features: const {'returns': true, 'store_credit': false},
    capabilities: const {'vendors', 'bundle', 'returns', 'account'},
  ),
);

/// The landing's recent searches (Figma 09b).
List<String> _recents(String locale) => locale == 'ar'
    ? const [
        'كنبة سرير',
        'مكتب',
        'حليب جهينة',
        'فستان مزهر',
        'تلفزيون سامسونج',
      ]
    : const [
        'sofa bed',
        'office desk',
        'juhayna milk',
        'floral dress',
        'samsung tv',
      ];

/// The top-level categories of Figma 09b's "Popular categories", with the
/// counts the tiles show ("7+ items").
List<Category> _popularTree(String locale) {
  final ar = locale == 'ar';
  Category category(
    int id,
    String key,
    String en,
    String arName,
    int count,
  ) => Category(
    uid: categoryUidFromId('$id'),
    name: ar ? arName : en,
    urlKey: key,
    productCount: count,
  );
  return [
    category(12, 'super-market', 'Grocery', 'سوبر ماركت', 7),
    category(14, 'clothes', 'Fashion', 'أزياء', 19),
    category(74, 'furniture', 'Furniture', 'أثاث', 7),
    category(21, 'electronics', 'Electronics & Tech', 'إلكترونيات وتقنية', 5),
    category(11, 'pharmacy', 'Pharmacy', 'صيدلية', 8),
    category(17, 'games', 'Kids & Toys', 'الأطفال والألعاب', 4),
  ];
}

/// Home's "Shop by category" chips in the admin's order, with the glyph and
/// the pastel slot each category carries — what the landing's tiles reuse.
HmHome _homeWithChips(List<Category> tree) {
  const icons = {
    'super-market': ('🛒', 0),
    'clothes': ('👗', 3),
    'furniture': ('🛋️', 2),
    'electronics': ('📱', 7),
    'pharmacy': ('💊', 1),
    'games': ('🧸', 5),
  };
  return HmHome(
    storeCode: 'en',
    sections: [
      HmHomeSection(
        id: 1,
        type: HmSectionType.categoryChips,
        categories: [
          for (var i = 0; i < tree.length; i++)
            HmCategoryChip(
              id: i + 1,
              uid: tree[i].uid,
              name: tree[i].name,
              urlKey: tree[i].urlKey,
              productCount: tree[i].productCount,
              icon: icons[tree[i].urlKey]?.$1,
              tint: icons[tree[i].urlKey]?.$2,
              link: HmLink(
                type: HmLinkType.category,
                url: 'https://hub-market.magento2.click/${tree[i].urlKey}',
                uid: tree[i].uid,
              ),
            ),
        ],
      ),
    ],
  );
}

/// The best sellers of Figma S2's "Popular right now": a seller line and the
/// first card's rating, as the frame draws them.
Map<String, dynamic> _bestSellers(String locale) {
  final data = bestSellersData(store: locale);
  final items =
      (data['hmBestSellers'] as Map<String, dynamic>)['items']
          as List<Map<String, dynamic>>;
  for (final (i, item) in items.indexed) {
    item['hm_seller'] = {
      '__typename': 'HmSellerSummary',
      'code': 'test1',
      'vendor_entity_id': 5,
      'name': 'Test 1',
      'logo_url': null,
      'rating': null,
      'review_count': 0,
      'product_count': 3,
      'is_marketplace': false,
      'link': null,
    };
    if (i == 0) {
      item['rating_summary'] = 50;
      item['review_count'] = 2;
    }
  }
  return data;
}

Widget _harness(
  GlobalKey boundary,
  FakeAlgoliaBackend algolia, {
  required String locale,
  String? initialQuery,
  bool hubApp = false,
  List<Category>? tree,
  List<String> recents = const <String>[],
  HmHome? home,
  List<String>? tries,
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
  final cache = FakeLocalCache();
  if (recents.isNotEmpty) {
    // The recent searches live in the local cache as one JSON list.
    cache.writeString('search_history', jsonEncode(recents));
  }
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(
          categories:
              tree ?? (locale == 'ar' ? kSearchTreeAr : kSearchTree),
        ),
      ),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(
        hubApp ? _hubApp(locale) : const HubAppState.unavailable(),
      ),
      if (hubApp)
        publicGraphqlClientProvider.overrideWithValue(
          FakeStoresBackend(
            (request) => request.operation == 'HmBestSellers'
                ? _bestSellers(locale)
                : storesAnswers(store: locale)(request),
          ).client,
        ),
      if (tries != null)
        searchTrySuggestionsProvider.overrideWith((ref, query) async => tries),
      if (home != null) hmHomeProvider.overrideWith((ref) async => home),
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

Future<void> _landing(WidgetTester tester, String locale) async {
  _phone(tester);
  final key = GlobalKey();
  final tree = _popularTree(locale);
  await tester.pumpWidget(
    _harness(
      key,
      FakeAlgoliaBackend(answer: _withoutImages(sofaAnswers(store: locale))),
      locale: locale,
      hubApp: true,
      tree: tree,
      recents: _recents(locale),
      home: _homeWithChips(tree),
    ),
  );
  await tester.pumpAndSettle();
  // The capture is of the page, not of a blinking caret.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await captureScreen(tester, key, 'audit_09b_search_landing_$locale');
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

Future<void> _results(
  WidgetTester tester,
  String locale, {
  required bool hubApp,
}) async {
  _phone(tester);
  final key = GlobalKey();
  await tester.pumpWidget(
    _harness(
      key,
      FakeAlgoliaBackend(answer: _algolia(locale)),
      locale: locale,
      initialQuery: locale == 'ar' ? 'كنبة' : 'sofa',
      hubApp: hubApp,
    ),
  );
  await tester.pumpAndSettle();
  await captureScreen(
    tester,
    key,
    'search_09c_results${hubApp ? '' : '_plain'}_$locale',
  );
}

Future<void> _noResults(
  WidgetTester tester,
  String locale, {
  required bool hubApp,
}) async {
  _phone(tester);
  final key = GlobalKey();
  await tester.pumpWidget(
    _harness(
      key,
      FakeAlgoliaBackend(answer: _algolia(locale, products: false)),
      locale: locale,
      hubApp: hubApp,
      // The store's query-suggestions index, which Hub Market has not switched
      // on yet (see `searchTrySuggestionsProvider`): the frame shows it on.
      tries: hubApp
          ? (locale == 'ar'
                ? const ['كنبة سرير', 'كنبة خضراء', 'أثاث']
                : const ['sofa bed', 'green sofa', 'Furniture'])
          : null,
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
  await captureScreen(
    tester,
    key,
    'search_S2_no_results${hubApp ? '' : '_plain'}_$locale',
  );
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('landing (09b) renders in $locale', (tester) async {
      await withRealShadows(() => _landing(tester, locale));
      final l10n = lookupAppLocalizations(Locale(locale));
      expect(find.text(l10n.searchRecentTitle), findsOneWidget);
      expect(find.text(l10n.searchTrendingTitle), findsOneWidget);
      expect(find.text(l10n.searchPopularCategories), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('type-ahead (09) renders in $locale', (tester) async {
      await withRealShadows(() => _typeAhead(tester, locale));
      expect(find.byType(SearchByAlgolia), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('results (09c) render in $locale', (tester) async {
      await withRealShadows(() => _results(tester, locale, hubApp: true));
      expect(
        find.text(locale == 'ar' ? 'المنتجات (12)' : 'Products (12)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('results (09c) render without the Hub Market App in $locale', (
      tester,
    ) async {
      await withRealShadows(() => _results(tester, locale, hubApp: false));
      expect(
        find.text(locale == 'ar' ? 'المنتجات (12)' : 'Products (12)'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('no results (S2) renders in $locale', (tester) async {
      await withRealShadows(() => _noResults(tester, locale, hubApp: true));
      expect(tester.takeException(), isNull);
    });

    testWidgets('no results (S2) renders without the Hub Market App in $locale',
        (tester) async {
      await withRealShadows(() => _noResults(tester, locale, hubApp: false));
      expect(tester.takeException(), isNull);
    });
  }
}
