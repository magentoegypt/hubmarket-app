import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_style.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_type_ahead.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

// The live shape of a Hub Market search (checked 2026-09-29): hits filed under
// a top-level category and a deeper one, a hidden "All" category, and a
// `category_uid` aggregation that also lists categories no hit reveals.
const _furnitureUid = 'NzQ=';
const _homeFurnitureUid = 'NzU=';
const _livingRoomUid = 'Nzc=';

const List<Category> _tree = <Category>[
  Category(
    uid: _furnitureUid,
    name: 'Furniture',
    urlKey: 'furniture',
    productCount: 7,
    children: <Category>[
      Category(
        uid: _homeFurnitureUid,
        name: 'Home Furniture',
        urlKey: 'home-furniture',
        productCount: 5,
      ),
      Category(
        uid: _livingRoomUid,
        name: 'Living Room Sets',
        urlKey: 'living-room-sets',
        productCount: 3,
      ),
    ],
  ),
  Category(uid: 'MTQw', name: 'Fashion', urlKey: 'fashion', productCount: 19),
  // Empty scaffolding category: neither a popular tile nor a scope choice.
  Category(uid: 'OTk=', name: 'Promotions', urlKey: 'promotions'),
];

const _furniture = ProductCategoryRef(
  uid: _furnitureUid,
  name: 'Furniture',
  level: 2,
);
const _homeFurniture = ProductCategoryRef(
  uid: _homeFurnitureUid,
  name: 'Home Furniture',
  level: 3,
);

const List<Product> _hits = <Product>[
  Product(
    sku: 'sofabed123',
    name: 'Corner Sofa Bed',
    urlKey: 'corner-sofa-bed',
    regularPrice: Money(amount: 500, currency: 'AED'),
    finalPrice: Money(amount: 425, currency: 'AED'),
    categories: <ProductCategoryRef>[
      _furniture,
      ProductCategoryRef(
        uid: _livingRoomUid,
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

const List<Aggregation> _aggregations = <Aggregation>[
  Aggregation(
    attributeCode: 'category_uid',
    label: 'Category',
    options: <AggregationOption>[
      AggregationOption(label: 'Furniture', value: _furnitureUid, count: 3),
      // Filed on a hit with include_in_menu 0 — never offered.
      AggregationOption(label: 'All', value: 'MTY4', count: 3),
      AggregationOption(
        label: 'Home Furniture',
        value: _homeFurnitureUid,
        count: 2,
      ),
      AggregationOption(
        label: 'Living Room Sets',
        value: _livingRoomUid,
        count: 1,
      ),
      // Neither on a loaded hit nor in the menu tree — unknown, so dropped.
      AggregationOption(label: 'Gear', value: 'Mw==', count: 1),
    ],
  ),
];

/// The catalogue fake, recording what each search asked for.
class _SearchCatalog extends FakeCatalogRepository {
  _SearchCatalog({super.products = _hits})
    : super(categories: _tree, aggregations: _aggregations);

  final List<({String? search, String? categoryUid})> calls = [];

  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? manufacturerId,
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
      manufacturerId: manufacturerId,
      pageSize: pageSize,
      currentPage: currentPage,
    );
  }
}

Widget _harness({
  required FakeCatalogRepository catalog,
  FakeLocalCache? cache,
  String locale = 'en',
  String? initialQuery,
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
        builder: (_, state) =>
            Scaffold(body: Text('PDP ${state.pathParameters['urlKey']}')),
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
      localCacheProvider.overrideWithValue(cache ?? FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(catalog),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
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

      await tester.pumpWidget(
        _harness(catalog: _SearchCatalog(), cache: cache),
      );
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

    testWidgets('numbered trending searches and popular category tiles', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(catalog: _SearchCatalog()));
      await tester.pumpAndSettle();

      // No history yet → no Recent section.
      expect(find.text('Recent searches'), findsNothing);
      expect(find.text('Trending searches'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('bag'), findsOneWidget);
      expect(find.text('Samsung'), findsOneWidget);

      expect(find.text('Popular categories'), findsOneWidget);
      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('7+ items'), findsOneWidget);
      expect(find.text('19+ items'), findsOneWidget);
      // A category with no products is never a tile.
      expect(find.text('Promotions'), findsNothing);

      await tester.tap(find.text('Furniture'));
      await tester.pumpAndSettle();
      expect(find.text('PLP $_furnitureUid'), findsOneWidget);
    });

    testWidgets('a trending search runs and lands in history', (tester) async {
      await _phone(tester);
      final cache = FakeLocalCache();
      await tester.pumpWidget(
        _harness(catalog: _SearchCatalog(), cache: cache),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('bag'));
      await tester.pumpAndSettle();

      expect(find.text('Products (3)'), findsOneWidget);
      expect(jsonDecode(cache.readString('search_history')!), ['bag']);
    });
  });

  group('type-ahead (Figma 09)', () {
    testWidgets(
      'hits with the typed word highlighted, "in <category>", prices',
      (tester) async {
        await _phone(tester);
        await tester.pumpWidget(_harness(catalog: _SearchCatalog()));
        await tester.pumpAndSettle();
        await _type(tester, 'sofa');

        expect(find.text('All categories'), findsOneWidget);
        expect(find.text('PRODUCTS'), findsOneWidget);
        expect(find.byType(SearchHighlightedText), findsNWidgets(3));

        final spans = _spansOf(tester, 'Corner Sofa Bed');
        final match = spans.singleWhere((s) => s.text == 'Sofa');
        expect(match.style?.fontWeight, FontWeight.w700);
        expect(match.style?.color, AppColors.accentStrong);
        expect(spans.map((s) => s.text), ['Corner ', 'Sofa', ' Bed']);

        // The deepest menu category the hit is filed under.
        expect(find.text('in Living Room Sets'), findsOneWidget);
        expect(find.text('in Home Furniture'), findsNWidgets(2));
        // Final price, and the regular one struck through when discounted.
        expect(find.text('AED 425.00'), findsOneWidget);
        expect(find.text('AED 500.00'), findsOneWidget);
        expect(find.text('AED 180.00'), findsOneWidget);
      },
    );

    testWidgets('pinned bar: category chips from the aggregation, View all N', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(catalog: _SearchCatalog()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      final chips = find.byType(SearchOutlinedChip);
      String chipLabel(int i) =>
          tester.widget<SearchOutlinedChip>(chips.at(i)).label;
      // Match count first, deeper first on a tie; the hidden "All" and the
      // unknown "Gear" are left out.
      expect(chips, findsNWidgets(3));
      expect(
        [chipLabel(0), chipLabel(1), chipLabel(2)],
        ['Furniture', 'Home Furniture', 'Living Room Sets'],
      );
      expect(find.text('All'), findsNothing);
      expect(find.text('Gear'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(SearchByAlgolia),
          matching: find.text('Search by algolia'),
        ),
        findsOneWidget,
      );

      // The top two categories are linked in the line under the hits.
      expect(
        find.text(
          'See products in All departments (3) or in Furniture, Home Furniture',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('View all 3 results'));
      await tester.pumpAndSettle();

      expect(find.text('Products (3)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
      expect(find.text('3 results for “${_typed('sofa')}”'), findsOneWidget);
    });

    testWidgets('"All departments (N)" opens the results, a category its PLP', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(catalog: _SearchCatalog()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      final line = find.textContaining('See products in');
      await tester.tapOnText(
        find.textRange.ofSubstring('Home Furniture', descendentOf: line),
      );
      await tester.pumpAndSettle();
      expect(find.text('PLP $_homeFurnitureUid'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring('All departments (3)'));
      await tester.pumpAndSettle();
      expect(find.text('Products (3)'), findsOneWidget);
    });

    testWidgets('a category chip opens that category\'s listing', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(catalog: _SearchCatalog()));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');

      await tester.tap(
        find.descendant(
          of: find.byType(SearchOutlinedChip),
          matching: find.text('Home Furniture'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PLP $_homeFurnitureUid'), findsOneWidget);
    });

    testWidgets('the scope chip narrows the search to one top-level category', (
      tester,
    ) async {
      await _phone(tester);
      final catalog = _SearchCatalog();
      await tester.pumpWidget(_harness(catalog: catalog));
      await tester.pumpAndSettle();
      await _type(tester, 'sofa');
      expect(catalog.calls.last, (search: 'sofa', categoryUid: null));

      await tester.tap(find.text('All categories'));
      await tester.pumpAndSettle();
      final sheet = find.byType(SearchScopeSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Search in')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Fashion')),
        findsOneWidget,
      );
      // Only top-level categories that hold products are offered.
      expect(find.text('Promotions'), findsNothing);
      expect(
        find.descendant(of: sheet, matching: find.text('Living Room Sets')),
        findsNothing,
      );
      await tester.tap(
        find.descendant(of: sheet, matching: find.text('Furniture')),
      );
      await tester.pumpAndSettle();

      expect(catalog.calls.last, (search: 'sofa', categoryUid: _furnitureUid));
      // The chip and the first link name the scope, which the category chips
      // then leave out.
      expect(find.text('All categories'), findsNothing);
      expect(
        find.textContaining('See products in Furniture (3)'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(SearchOutlinedChip),
          matching: find.text('Furniture'),
        ),
        findsNothing,
      );
    });

    testWidgets('no results shows S2 (Popular right now is Build 2)', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(catalog: _SearchCatalog(products: const <Product>[])),
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
      expect(find.text('View all 0 results'), findsNothing);
    });

    testWidgets('Arabic is right-to-left with the AR frame\'s copy', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(catalog: _SearchCatalog(), locale: 'ar'),
      );
      await tester.pumpAndSettle();

      expect(find.text('الأكثر بحثًا'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
      final direction = Directionality.of(
        tester.element(find.text('الأكثر بحثًا')),
      );
      expect(direction, TextDirection.rtl);

      await _type(tester, 'sofa');
      expect(find.text('كل الأقسام'), findsOneWidget);
      expect(find.text('المنتجات'), findsOneWidget);
      // Category names come from the store view's data.
      expect(find.text('في Home Furniture'), findsNWidgets(2));
      expect(
        find.text(
          'اعرض المنتجات في كل الأقسام (3) أو في Furniture، Home Furniture',
        ),
        findsOneWidget,
      );
      expect(find.text('عرض كل النتائج (3)'), findsOneWidget);
      // The attribution stays an English, left-to-right lockup.
      final lockup = find.descendant(
        of: find.byType(SearchByAlgolia),
        matching: find.text('Search by algolia'),
      );
      expect(Directionality.of(tester.element(lockup)), TextDirection.ltr);
    });
  });

  group('results (Figma 09c)', () {
    testWidgets('Products and Categories tabs; a category row opens its PLP', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(catalog: _SearchCatalog(), initialQuery: 'sofa'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Products (3)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
      expect(find.text('3 results for “${_typed('sofa')}”'), findsOneWidget);
      expect(find.text('Relevance'), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Corner Sofa Bed'), findsOneWidget);
      // The results page has a back arrow and no Cancel.
      expect(find.text('Cancel'), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      await tester.tap(find.text('Categories (3)'));
      await tester.pumpAndSettle();

      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('3 matching products'), findsOneWidget);
      expect(find.text('Home Furniture'), findsOneWidget);
      expect(find.text('2 matching products'), findsOneWidget);
      expect(find.text('1 matching product'), findsOneWidget);

      await tester.tap(find.text('Living Room Sets'));
      await tester.pumpAndSettle();
      expect(find.text('PLP $_livingRoomUid'), findsOneWidget);
    });

    testWidgets('sort and filter open the shared sheets', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(catalog: _SearchCatalog(), initialQuery: 'sofa'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Relevance'));
      await tester.pumpAndSettle();
      expect(find.text('Price: Low to High'), findsOneWidget);
      await tester.tap(find.text('Price: Low to High'));
      await tester.pumpAndSettle();
      // The action names the active sort.
      expect(find.text('Price: Low to High'), findsOneWidget);
      expect(find.text('Relevance'), findsNothing);

      await tester.tap(find.text('Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Apply Filters'), findsOneWidget);
    });

    testWidgets(
      'tapping the field goes back to the type-ahead; Cancel returns',
      (tester) async {
        await _phone(tester);
        await tester.pumpWidget(
          _harness(catalog: _SearchCatalog(), initialQuery: 'sofa'),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(find.text('View all 3 results'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.text('Products (3)'), findsOneWidget);
      },
    );
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
