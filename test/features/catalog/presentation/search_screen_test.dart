import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_providers.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_card.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_style.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_type_ahead.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

// ---------------------------------------------------------------- GraphQL

const _furniture = ProductCategoryRef(
  uid: kFurnitureUid,
  name: 'Furniture',
  level: 2,
);
const _homeFurniture = ProductCategoryRef(
  uid: kHomeFurnitureUid,
  name: 'Home Furniture',
  level: 3,
);

/// What GraphQL `products(search:)` answers — the fallback.
const List<Product> _graphqlHits = <Product>[
  Product(
    sku: 'sofabed123',
    name: 'Corner Sofa Bed',
    urlKey: 'corner-sofa-bed',
    regularPrice: Money(amount: 500, currency: 'AED'),
    finalPrice: Money(amount: 425, currency: 'AED'),
    categories: <ProductCategoryRef>[
      _furniture,
      ProductCategoryRef(
        uid: kLivingRoomUid,
        name: 'Living Room Sets',
        level: 3,
      ),
    ],
  ),
  Product(
    sku: 'chair-gold',
    name: 'Dining Chair with Gold Metal Legs',
    urlKey: 'dining-chair-gold',
    regularPrice: Money(amount: 40, currency: 'AED'),
    finalPrice: Money(amount: 34, currency: 'AED'),
    categories: <ProductCategoryRef>[_furniture, _homeFurniture],
  ),
  Product(
    sku: 'rocking-chair',
    name: 'Burgundy Rocking Chair',
    urlKey: 'burgundy-rocking-chair',
    regularPrice: Money(amount: 180, currency: 'AED'),
    finalPrice: Money(amount: 180, currency: 'AED'),
    categories: <ProductCategoryRef>[
      _furniture,
      _homeFurniture,
      ProductCategoryRef(uid: 'MTY4', name: 'All', level: 2, inMenu: false),
    ],
  ),
];

const List<Aggregation> _graphqlAggregations = <Aggregation>[
  Aggregation(
    attributeCode: 'category_uid',
    label: 'Category',
    options: <AggregationOption>[
      AggregationOption(label: 'Furniture', value: kFurnitureUid, count: 3),
      // Filed on a hit with include_in_menu 0 — never offered.
      AggregationOption(label: 'All', value: 'MTY4', count: 3),
      AggregationOption(
        label: 'Home Furniture',
        value: kHomeFurnitureUid,
        count: 2,
      ),
      AggregationOption(
        label: 'Living Room Sets',
        value: kLivingRoomUid,
        count: 1,
      ),
      // Neither on a loaded hit nor in the menu tree — unknown, so dropped.
      AggregationOption(label: 'Gear', value: 'Mw==', count: 1),
    ],
  ),
];

/// The GraphQL catalogue, recording what each search asked for.
class _SearchCatalog extends FakeCatalogRepository {
  _SearchCatalog()
    : super(
        products: _graphqlHits,
        categories: kSearchTree,
        aggregations: _graphqlAggregations,
      );

  final List<({String? search, String? categoryUid})> calls = [];

  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? brandOptionId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) {
    calls.add((search: search, categoryUid: categoryUid));
    return super.fetchProducts(
      search: search,
      categoryUid: categoryUid,
      brandOptionId: brandOptionId,
      pageSize: pageSize,
      currentPage: currentPage,
    );
  }
}

/// The cart, recording what went in by SKU.
class _Cart extends FakeCartRepository {
  final List<String> added = [];

  @override
  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    bool throwOnUserError = true,
  }) {
    added.addAll(items.map((item) => item['sku'] as String));
    return super.addProducts(cartId, items, throwOnUserError: throwOnUserError);
  }
}

/// The search screen with routes for everything it opens. [algolia] null
/// means Algolia can't answer (its settings page is down): the GraphQL
/// fallback searches.
Widget _harness({
  FakeAlgoliaBackend? algolia,
  _SearchCatalog? catalog,
  FakeLocalCache? cache,
  _Cart? cart,
  String locale = 'en',
  String? initialQuery,
  HubAppState hubApp = const HubAppState.unavailable(),
}) {
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder: (_, __) => SearchScreen(initialQuery: initialQuery),
      ),
      GoRoute(
        path: '/category/:uid',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('PLP ${state.pathParameters['uid']}'),
        ),
      ),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('PDP ${state.pathParameters['urlKey']}'),
        ),
      ),
      GoRoute(
        path: '/page',
        builder: (_, state) => Scaffold(
          body: Text(
            'CMS ${state.uri.queryParameters['url']} · '
            '${state.uri.queryParameters['title']}',
          ),
        ),
      ),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/checkout',
        '/wishlist',
        '/account',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(cache ?? FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(catalog ?? _SearchCatalog()),
      cartRepositoryProvider.overrideWithValue(cart ?? _Cart()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      // HubApp's public reads (store-name matches) stay offline too.
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      algoliaHttpClientProvider.overrideWithValue(
        (algolia ?? FakeAlgoliaBackend(pageStatus: 503)).client,
      ),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

FakeAlgoliaBackend _algolia({
  bool products = true,
  bool suggestions = true,
  String store = 'en',
}) => FakeAlgoliaBackend(
  answer: sofaAnswers(
    products: products,
    suggestions: suggestions,
    store: store,
  ),
);

/// The typed query as the copy embeds it: wrapped in Unicode isolates so it
/// keeps its order inside right-to-left sentences.
String _typed(String query) => '\u2068$query\u2069';

/// A phone-sized surface, so the pinned bar and tabs lay out as on a device.
Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

/// Types [text] and lets the type-ahead's debounce and fetch complete.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

/// Every leaf span of the [RichText] that paints exactly [text].
List<TextSpan> _spansOf(WidgetTester tester, String text) {
  final rich = tester.widget<RichText>(
    find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == text,
    ),
  );
  final leaves = <TextSpan>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text != null) leaves.add(span);
    return true;
  });
  return leaves;
}

/// The products searches Algolia was asked (not the count-only ones).
List<RecordedQuery> _productSearches(FakeAlgoliaBackend algolia) => [
  for (final q in algolia.queries)
    if (q.indexName.contains('_products') && q.params['hitsPerPage'] != '0') q,
];

Finder _chip(String label) => find.descendant(
  of: find.byType(SearchOutlinedChip),
  matching: find.text(label),
);

void main() {
  group('landing (Figma 09b)', () {
    testWidgets('recent searches: a row\'s (x) removes just that entry', (
      tester,
    ) async {
      await _phone(tester);
      final cache = FakeLocalCache();
      await cache.writeString(
        'search_history',
        jsonEncode(['sofa bed', 'office desk', 'juhayna milk']),
      );

      await tester.pumpWidget(_harness(cache: cache));
      await tester.pumpAndSettle();

      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('office desk'), findsOneWidget);

      final remove = find.descendant(
        of: find.ancestor(
          of: find.text('office desk'),
          matching: find.byType(InkWell),
        ),
        matching: find.byTooltip('Remove from recent searches'),
      );
      await tester.tap(remove.first);
      await tester.pumpAndSettle();

      expect(find.text('office desk'), findsNothing);
      expect(find.text('sofa bed'), findsOneWidget);
      expect(find.text('juhayna milk'), findsOneWidget);
      expect(jsonDecode(cache.readString('search_history')!), [
        'sofa bed',
        'juhayna milk',
      ]);
    });

    testWidgets('Build 1: no trending list to show, popular category tiles', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness());
      await tester.pumpAndSettle();

      // No history yet → no Recent section.
      expect(find.text('Recent searches'), findsNothing);
      // Without the admin's list the section is left out: the app has no
      // trending terms of its own (QA02).
      expect(find.text('Trending searches'), findsNothing);
      expect(find.text('bag'), findsNothing);
      expect(find.text('Samsung'), findsNothing);

      expect(find.text('Popular categories'), findsOneWidget);
      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('7+ items'), findsOneWidget);
      expect(find.text('19+ items'), findsOneWidget);
      // A category with no products is never a tile.
      expect(find.text('Promotions'), findsNothing);

      await tester.tap(find.text('Furniture'));
      await tester.pumpAndSettle();
      expect(find.text('PLP $kFurnitureUid'), findsOneWidget);
    });

    testWidgets(
      'the Hub Market App settings give the hint and the trending list',
      (tester) async {
        await _phone(tester);
        await tester.pumpWidget(
          _harness(hubApp: const HubAppState.available(kSampleHmAppConfig)),
        );
        await tester.pumpAndSettle();

        expect(find.text('Search 20,000+ products'), findsOneWidget);
        expect(find.text('Trending searches'), findsOneWidget);
        // Numbered in the admin's order.
        expect(find.text('1'), findsOneWidget);
        expect(find.text('iphone'), findsOneWidget);
        expect(find.text('abaya'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.text('rice'), findsOneWidget);
      },
    );

    testWidgets('a trending search runs and lands in history', (tester) async {
      await _phone(tester);
      final cache = FakeLocalCache();
      final algolia = _algolia();
      await tester.pumpWidget(
        _harness(
          algolia: algolia,
          cache: cache,
          hubApp: const HubAppState.available(kSampleHmAppConfig),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('abaya'));
      await tester.pumpAndSettle();

      expect(find.text('Products (12)'), findsOneWidget);
      expect(jsonDecode(cache.readString('search_history')!), ['abaya']);
      expect(_productSearches(algolia).last.query, 'abaya');
    });

    testWidgets('opening search loads the store view\'s Algolia settings', (
      tester,
    ) async {
      await _phone(tester);
      final algolia = _algolia();
      await tester.pumpWidget(_harness(algolia: algolia));
      await tester.pumpAndSettle();

      expect(algolia.pageRequests.single.url.path, '/en/');
      expect(algolia.algoliaRequests, isEmpty);
    });
  });

  group('type-ahead (Figma 09) on Algolia', () {
    testWidgets('hits with Algolia\'s highlight, "in <category>", prices', (
      tester,
    ) async {
      await _phone(tester);
      final algolia = _algolia();
      await tester.pumpWidget(_harness(algolia: algolia));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      // One round trip: products, categories and pages of the EN store.
      expect(algolia.algoliaRequests, hasLength(1));
      expect(algolia.lastCall.map((q) => q.indexName), [
        'hubmarket_en_products',
        'hubmarket_en_categories',
        'hubmarket_en_pages',
      ]);
      expect(algolia.lastCall.first.query, 'sofa');

      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('PRODUCTS'), findsOneWidget);
      expect(find.byType(SearchHighlightedText), findsNWidgets(4));

      final spans = _spansOf(tester, 'Corner Sofa Bed');
      final match = spans.singleWhere((s) => s.text == 'Sofa');
      expect(match.style?.fontWeight, FontWeight.w700);
      expect(match.style?.color, AppColors.accentStrong);
      expect(spans.map((s) => s.text), ['Corner ', 'Sofa', ' Bed']);

      // The deepest category of each record.
      expect(find.text('in Living Room Sets'), findsNWidgets(2));
      expect(find.text('in Home Furniture'), findsNWidgets(2));
      // Price in AED, the original struck through when there is one.
      expect(find.text('AED 425'), findsOneWidget);
      expect(find.text('AED 500'), findsOneWidget);
      expect(find.text('AED 180'), findsOneWidget);
      final struck = tester.widget<Text>(find.text('AED 500'));
      expect(struck.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('categories and pages suggestions, View all N, attribution', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(algolia: _algolia()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      // The top two categories of the matches, from the categoryIds facet.
      expect(
        find.text(
          'See products in All departments (12) or in Furniture, '
          'Living Room Sets',
        ),
        findsOneWidget,
      );
      // Each chip row carries its label (the tab bar says "Categories" too).
      Finder rowOf(String chip) =>
          find.ancestor(of: _chip(chip), matching: find.byType(Row)).last;
      expect(
        find.descendant(
          of: rowOf('Living Room Sets'),
          matching: find.text('Categories'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowOf('Shipping & delivery'),
          matching: find.text('Pages'),
        ),
        findsOneWidget,
      );
      expect(_chip('Living Room Sets'), findsOneWidget);
      expect(_chip('Shipping & delivery'), findsOneWidget);
      expect(_chip('Return policy'), findsOneWidget);
      expect(find.text('View all 12 results'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SearchByAlgolia),
          matching: find.text('Search by algolia'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('View all 12 results'));
      await tester.pumpAndSettle();
      expect(find.text('Products (12)'), findsOneWidget);
      expect(find.text('12 results for “${_typed('sofa')}”'), findsOneWidget);
    });

    testWidgets('a product opens its PDP by the url_key of its URL', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(algolia: _algolia()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      await tester.tap(find.text('Burgundy Rocking Chair'));
      await tester.pumpAndSettle();
      expect(find.text('PDP chairs126'), findsOneWidget);
    });

    testWidgets('a category chip opens its listing by the id\'s uid', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(algolia: _algolia()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      await tester.tap(_chip('Living Room Sets'));
      await tester.pumpAndSettle();
      expect(find.text('PLP $kLivingRoomUid'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      final line = find.textContaining('See products in');
      await tester.tapOnText(
        find.textRange.ofSubstring('Furniture', descendentOf: line),
      );
      await tester.pumpAndSettle();
      expect(find.text('PLP $kFurnitureUid'), findsOneWidget);
    });

    testWidgets('a page chip opens the native CMS page by its path', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(algolia: _algolia()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      await tester.tap(_chip('Shipping & delivery'));
      await tester.pumpAndSettle();
      expect(
        find.text('CMS shipping-delivery · Shipping & delivery'),
        findsOneWidget,
      );
    });

    testWidgets('the scope chip narrows the products to one category', (
      tester,
    ) async {
      await _phone(tester);
      final algolia = _algolia();
      await tester.pumpWidget(_harness(algolia: algolia));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');
      expect(algolia.lastCall.first.json('facetFilters'), isNull);

      await tester.tap(find.text('All categories'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SearchScopeSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Search in')),
        findsOneWidget,
      );
      // Only top-level categories that hold products are offered.
      expect(find.text('Promotions'), findsNothing);
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Furniture')),
      );
      await tester.pumpAndSettle();

      expect(algolia.lastCall.first.json('facetFilters'), ['categoryIds:74']);
      expect(
        find.textContaining('See products in Furniture (12)'),
        findsOneWidget,
      );
    });

    testWidgets('nothing matches: the S2 page', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(algolia: _algolia(products: false, suggestions: false)),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'sofa bed velvet green');

      expect(
        find.text('No results for “${_typed('sofa bed velvet green')}”'),
        findsOneWidget,
      );
      expect(
        find.text('Check the spelling or use fewer words.'),
        findsOneWidget,
      );
      expect(find.text('Popular right now'), findsNothing);
      expect(find.textContaining('View all'), findsNothing);
    });

    testWidgets('no product, but pages match: S2 keeps the pages', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(algolia: _algolia(products: false)));
      await tester.pumpAndSettle();
      await _type(tester, 'shipping');

      expect(
        find.text('No results for “${_typed('shipping')}”'),
        findsOneWidget,
      );
      expect(_chip('Shipping & delivery'), findsOneWidget);
      expect(find.textContaining('View all'), findsNothing);
    });

    testWidgets('Arabic searches the AR indices, right to left', (
      tester,
    ) async {
      await _phone(tester);
      final algolia = _algolia(store: 'ar');
      await tester.pumpWidget(_harness(algolia: algolia, locale: 'ar'));
      await tester.pumpAndSettle();

      // Build 1: no trending list, so the categories head the landing.
      expect(find.text('الأكثر بحثًا'), findsNothing);
      expect(find.text('الأقسام الأكثر رواجًا'), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('الأقسام الأكثر رواجًا'))),
        TextDirection.rtl,
      );

      await _type(tester, 'كنبة');
      expect(algolia.pageRequests.single.url.path, '/ar/');
      expect(algolia.lastCall.map((q) => q.indexName), [
        'hubmarket_ar_products',
        'hubmarket_ar_categories',
        'hubmarket_ar_pages',
      ]);
      expect(find.text('كل الأقسام'), findsOneWidget);
      expect(find.text('المنتجات'), findsOneWidget);
      expect(find.text('في أطقم غرف المعيشة'), findsNWidgets(2));
      expect(find.text('الصفحات'), findsOneWidget);
      expect(_chip('سياسة الإرجاع'), findsOneWidget);
      expect(find.text('عرض كل النتائج (12)'), findsOneWidget);
      final spans = _spansOf(tester, 'كنبة سرير ركنه');
      expect(spans.first.text, 'كنبة');
      expect(spans.first.style?.fontWeight, FontWeight.w700);
      // The attribution stays an English, left-to-right lockup.
      final lockup = find.descendant(
        of: find.byType(SearchByAlgolia),
        matching: find.text('Search by algolia'),
      );
      expect(Directionality.of(tester.element(lockup)), TextDirection.ltr);
    });
  });

  group('type-ahead fallback (Algolia unavailable)', () {
    testWidgets('GraphQL answers; no pages, no attribution', (tester) async {
      await _phone(tester);
      final catalog = _SearchCatalog();
      await tester.pumpWidget(_harness(catalog: catalog));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      expect(catalog.calls.last, (search: 'sofa', categoryUid: null));
      expect(find.byType(SearchHighlightedText), findsNWidgets(3));
      expect(_spansOf(tester, 'Corner Sofa Bed').map((s) => s.text), [
        'Corner ',
        'Sofa',
        ' Bed',
      ]);
      expect(find.text('in Living Room Sets'), findsOneWidget);
      expect(find.text('in Home Furniture'), findsNWidgets(2));
      // The result's categories as chips, as before Algolia.
      expect(_chip('Furniture'), findsOneWidget);
      expect(_chip('Home Furniture'), findsOneWidget);
      expect(find.text('Pages'), findsNothing);
      expect(find.text('View all 3 results'), findsOneWidget);
      expect(find.byType(SearchByAlgolia), findsNothing);

      await tester.tap(find.text('View all 3 results'));
      await tester.pumpAndSettle();
      expect(find.text('Products (3)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
    });

    testWidgets('a refused key also falls back', (tester) async {
      await _phone(tester);
      final algolia = FakeAlgoliaBackend(algoliaStatus: 403);
      await tester.pumpWidget(_harness(algolia: algolia));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      // Algolia refused twice (the second time with a fresh key).
      expect(algolia.algoliaRequests, hasLength(2));
      expect(find.text('View all 3 results'), findsOneWidget);
      expect(find.byType(SearchByAlgolia), findsNothing);
    });
  });

  group('results (Figma 09c) on Algolia', () {
    testWidgets('tabs, count, Relevance; Categories tab opens a listing', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(algolia: _algolia(), initialQuery: 'sofa'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Products (12)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
      expect(find.text('12 results for “${_typed('sofa')}”'), findsOneWidget);
      expect(find.text('Relevance'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Corner Sofa Bed'), findsOneWidget);
      // AED 425 of 500, 255 of 300, 34 of 40.
      expect(find.text('-15%'), findsNWidgets(3));
      expect(find.text('Cancel'), findsNothing);
      expect(find.byIcon(HubIcons.arrowLeft), findsOneWidget);

      await tester.tap(find.text('Categories (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('12 matching products'), findsOneWidget);
      expect(find.text('5 matching products'), findsOneWidget);
      await tester.tap(find.text('Living Room Sets'));
      await tester.pumpAndSettle();
      expect(find.text('PLP $kLivingRoomUid'), findsOneWidget);
    });

    testWidgets('Algolia paging: scrolling asks for the next page', (
      tester,
    ) async {
      await _phone(tester);
      final algolia = _algolia();
      await tester.pumpWidget(_harness(algolia: algolia, initialQuery: 'sofa'));
      await tester.pumpAndSettle();
      expect(_productSearches(algolia).single.params['page'], '0');
      expect(_productSearches(algolia).single.params['hitsPerPage'], '20');

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();

      expect(_productSearches(algolia).last.params['page'], '1');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(find.text('Velvet Sofa'), findsOneWidget);
      // The last page: no more requests.
      final asked = _productSearches(algolia).length;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(_productSearches(algolia), hasLength(asked));
    });

    testWidgets('sorts are the configured replicas, Relevance first', (
      tester,
    ) async {
      await _phone(tester);
      final algolia = _algolia();
      await tester.pumpWidget(_harness(algolia: algolia, initialQuery: 'sofa'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Relevance'));
      await tester.pumpAndSettle();
      expect(find.text('Lowest price'), findsOneWidget);
      expect(find.text('Highest price'), findsOneWidget);
      expect(find.text('Newest first'), findsOneWidget);
      // No replica sorts by name, so neither does the app on Algolia.
      expect(find.text('Name: A–Z'), findsNothing);

      await tester.tap(find.text('Newest first'));
      await tester.pumpAndSettle();
      expect(
        _productSearches(algolia).last.indexName,
        'hubmarket_en_products_created_at_desc',
      );
      expect(find.text('Newest first'), findsOneWidget);
      expect(find.text('Relevance'), findsNothing);
    });

    testWidgets('filters are the index\'s facets, with its labels', (
      tester,
    ) async {
      // A tall phone: the sheet lists its sections lazily, and there are more
      // of them now (Sort by, Store, Customer rating) than a screen holds.
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final algolia = _algolia();
      await tester.pumpWidget(_harness(algolia: algolia, initialQuery: 'sofa'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Price (AED)'), findsOneWidget);
      expect(find.text('Categories'), findsWidgets);
      expect(find.text('Brand'), findsOneWidget);
      // The seller facet is the sheet's Store section.
      expect(find.text('Store'), findsOneWidget);
      // rating_summary is a facet, so "N★ & up" is offered.
      expect(find.text('Customer rating'), findsOneWidget);
      // The results' sorts are chips of the sheet too.
      expect(find.text('Sort by'), findsOneWidget);

      await tester.tap(find.text('Grey'));
      await tester.pump();
      // The button names how many results there are (12 for this search).
      await tester.tap(find.text('Show 12 results'));
      await tester.pumpAndSettle();

      final main = _productSearches(algolia).last;
      expect(main.json('facetFilters'), [
        ['color:Grey'],
      ]);
      // The color facet is counted without its own filter too.
      final counts = algolia.lastCall.where(
        (q) => q.params['hitsPerPage'] == '0',
      );
      expect(counts.single.json('facets'), ['color']);
      expect(find.text('Filter (1)'), findsOneWidget);
    });

    testWidgets('add to cart: a simple product by SKU, a configurable opens '
        'its PDP', (tester) async {
      await _phone(tester);
      final cart = _Cart();
      await tester.pumpWidget(
        _harness(algolia: _algolia(), initialQuery: 'sofa', cart: cart),
      );
      await tester.pumpAndSettle();

      Finder plusOf(String name) => find.descendant(
        of: find.ancestor(
          of: find.text(name),
          matching: find.byType(ProductCard),
        ),
        matching: find.byTooltip('Add to Cart'),
      );

      await tester.tap(plusOf('3-Piece Living Room Set'));
      await tester.pumpAndSettle();
      expect(cart.added, ['3-piece-set']);
      expect(find.text('Added to cart'), findsOneWidget);

      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      await tester.tap(plusOf('Corner Sofa Bed'));
      await tester.pumpAndSettle();
      expect(find.text('PDP sofabed123'), findsOneWidget);
      expect(cart.added, ['3-piece-set']);
    });

    testWidgets(
      'tapping the field goes back to the type-ahead; Cancel returns',
      (tester) async {
        await _phone(tester);
        await tester.pumpWidget(
          _harness(algolia: _algolia(), initialQuery: 'sofa'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(find.text('View all 12 results'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Products (12)'), findsOneWidget);
      },
    );
  });

  group('results fallback (Algolia unavailable)', () {
    testWidgets('GraphQL results with its own sorts and filters', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(initialQuery: 'sofa'));
      await tester.pumpAndSettle();

      expect(find.text('Products (3)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
      expect(find.text('3 results for “${_typed('sofa')}”'), findsOneWidget);

      await tester.tap(find.text('Relevance'));
      await tester.pumpAndSettle();
      expect(find.text('Lowest price'), findsOneWidget);
      expect(find.text('Name: A–Z'), findsOneWidget);
      expect(find.text('Newest first'), findsNothing);
      await tester.tap(find.text('Lowest price'));
      await tester.pumpAndSettle();
      expect(find.text('Lowest price'), findsOneWidget);
      expect(find.text('Relevance'), findsNothing);

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Show 3 results'), findsOneWidget);
      expect(find.text('Customer rating'), findsNothing);
    });
  });

  testWidgets('a brand landing still lists the brand\'s products', (
    tester,
  ) async {
    await _phone(tester);
    // No logo URL, so the header draws no network image.
    const brand = Brand(
      brandId: 114,
      title: 'Mancera',
      urlKey: 'Mancera',
      url: '',
      imageUrl: '',
      optionId: 126,
      position: 0,
    );
    final router = GoRouter(
      initialLocation: '/brand',
      routes: [
        GoRoute(
          path: '/brand',
          builder: (_, __) => const SearchScreen(brand: brand),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
          graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
          hubAppOverride(const HubAppState.unavailable()),
          algoliaHttpClientProvider.overrideWithValue(
            FakeAlgoliaBackend(pageStatus: 503).client,
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
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
    await tester.pumpAndSettle();

    expect(find.text('Mancera'), findsOneWidget);
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Coco Mademoiselle EDP'), findsOneWidget);
  });
}
