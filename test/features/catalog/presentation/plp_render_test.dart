import 'dart:async';

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
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/filter_sheet.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/sheet_chrome.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/sort_sheet.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';
import '../../stores/stores_harness.dart';

/// Renders the product listing (Figma 10 / AR 49:1539), its Filters sheet (11 /
/// AR 49:1757) and the sort sheet to `build/test_screens/` for comparison with
/// the frames, in English and Arabic. Each render also fails on any layout
/// exception, so it doubles as an RTL and overflow check.
///
/// Tests can't load network images: the cards show their placeholders.

Product _product(
  String locale,
  String sku,
  String en,
  String ar,
  double price, {
  double? regular,
  required double stars,
  required int reviews,
}) => Product(
  sku: sku,
  name: locale == 'ar' ? ar : en,
  urlKey: sku,
  regularPrice: Money(amount: regular ?? price, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
  ratingSummary: stars * 20,
  reviewCount: reviews,
  sellerName: locale == 'ar' ? 'ميا كو' : 'MIA CO',
  sellerKnown: true,
);

/// The products of Figma 10.
List<Product> _products(String locale) => [
  _product(
    locale,
    'corner-sofa',
    'Corner Sofa Bed',
    'كنبة سرير ركنه',
    425,
    regular: 500,
    stars: 4.6,
    reviews: 18,
  ),
  _product(
    locale,
    'living-set',
    '3-Piece Living Room Set',
    'غرفة معيشة 3 قطع',
    300,
    stars: 4.8,
    reviews: 12,
  ),
  _product(
    locale,
    'dining-chair',
    'Dining Chair with Gold Metal Legs',
    'كرسي طعام بارجل ذهبية معدنية',
    34,
    regular: 40,
    stars: 4.4,
    reviews: 9,
  ),
  _product(
    locale,
    'rocking-chair',
    'Burgundy Rocking Chair',
    'كرسي هزاز عنابي',
    180,
    stars: 4.7,
    reviews: 21,
  ),
];

/// The facets of Furniture's listing as the live API serves them: price
/// buckets, the vendor attribute (labels are vendor ids), a size.
List<Aggregation> _aggregations(String locale) => [
  const Aggregation(
    attributeCode: 'price',
    label: 'Price',
    options: [AggregationOption(label: '0-500', value: '0_500', count: 12)],
  ),
  Aggregation(
    attributeCode: 'category_uid',
    label: 'Category',
    options: [
      AggregationOption(
        label: 'Home Furniture',
        value: kHomeFurnitureUid,
        count: 5,
      ),
    ],
  ),
  const Aggregation(
    attributeCode: 'VENDORID',
    label: 'Vendor ID',
    options: [
      AggregationOption(label: '12', value: '522', count: 8),
      AggregationOption(label: '9', value: '523', count: 3),
      AggregationOption(label: '7', value: '524', count: 2),
      AggregationOption(label: '21', value: '525', count: 2),
    ],
  ),
  Aggregation(
    attributeCode: 'clothes_size',
    label: locale == 'ar' ? 'المقاس' : 'Size',
    options: const [
      AggregationOption(label: 'XS', value: '300', count: 1),
      AggregationOption(label: 'S', value: '301', count: 3),
      AggregationOption(label: 'M', value: '302', count: 5),
      AggregationOption(label: 'L', value: '303', count: 5),
      AggregationOption(label: 'XL', value: '304', count: 2),
    ],
  ),
];

/// The catalogue as the listing's frame has it: twelve products with a store
/// picked, eighteen without.
class _FrameCatalog extends FakeCatalogRepository {
  _FrameCatalog(this.locale)
    : super(categories: locale == 'ar' ? kSearchTreeAr : kSearchTree);

  final String locale;
  final List<Map<String, Set<String>>> asked = [];

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
  }) async {
    asked.add(attributeFilters);
    return ProductPage(
      items: _products(locale),
      totalCount: attributeFilters.isEmpty ? 18 : 12,
      currentPage: currentPage,
      totalPages: 1,
      aggregations: _aggregations(locale),
    );
  }
}

/// A router whose first page is an empty home and whose `/page` is [page]:
/// push it, so the page has a back step as it has in the app. With [open] the
/// page is the first one instead (a sheet's host).
GoRouter _router(Widget page, {bool open = false}) => GoRouter(
  initialLocation: open ? '/page' : '/home',
  routes: [
    GoRoute(path: '/page', builder: (_, __) => page),
    GoRoute(path: '/search', builder: (_, __) => const Scaffold()),
    for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account'])
      GoRoute(path: p, builder: (_, __) => const Scaffold()),
  ],
);

Widget _app(
  GlobalKey boundary, {
  required String locale,
  required GoRouter router,
  _FrameCatalog? catalog,
}) {
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(
        catalog ?? _FrameCatalog(locale),
      ),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.available(kVendorsHmAppConfig)),
      publicGraphqlClientProvider.overrideWithValue(
        FakeStoresBackend(storesAnswers(store: locale)).client,
      ),
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

void _surface(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Opens the sheet [builder] builds over an empty page, as the listing does.
Widget _sheetHost(WidgetBuilder builder) => Scaffold(
  backgroundColor: Colors.white,
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () =>
            showCatalogSheet<Object>(context: context, builder: builder),
        child: const Text('open'),
      ),
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('10 Product listing renders in $locale', (tester) async {
      _surface(tester);
      final key = GlobalKey();
      await withRealShadows(() async {
        final router = _router(
          PlpScreen(
            categoryUid: kHomeFurnitureUid,
            title: locale == 'ar' ? 'أثاث منزلي' : 'Home Furniture',
          ),
        );
        await tester.pumpWidget(_app(key, locale: locale, router: router));
        await tester.pumpAndSettle();
        unawaited(router.push('/page'));
        await tester.pumpAndSettle();
        // MIA CO picked in the sheet, as the frame has it.
        await tester.tap(find.text(l10n.filtersLabel));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(FilterSheet),
            matching: find.text(locale == 'ar' ? 'ميا كو' : 'MIA CO'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.filterShowResults(12)));
        await tester.pumpAndSettle();
        // The frame sorts by relevance (the listing opens on the highest price).
        await tester.tap(find.text(l10n.sortHighestPrice));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.sortRelevance));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'audit_10_plp_$locale');
      });
      // The chip of the store, the line and the sort.
      expect(find.text('${l10n.filtersLabel} · 1'), findsOneWidget);
      expect(
        find.text(
          l10n.categoryProductCountFrom(
            12,
            locale == 'ar' ? 'ميا كو' : 'MIA CO',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.sortRelevance), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('11 Filters sheet renders in $locale', (tester) async {
      _surface(tester, height: 963);
      final key = GlobalKey();
      await withRealShadows(() async {
        await tester.pumpWidget(
          _app(
            key,
            locale: locale,
            router: _router(
              open: true,
              _sheetHost(
                (context) => FilterSheet(
                  // The listing leaves its own category out of the sheet.
                  aggregations: [
                    for (final facet in _aggregations(locale))
                      if (facet.attributeCode != 'category_uid') facet,
                  ],
                  initial: const {
                    'VENDORID': {'522'},
                    'clothes_size': {'302'},
                  },
                  currency: 'AED',
                  initialPriceFrom: 30,
                  initialPriceTo: 450,
                  initialMinRating: 4,
                  showRating: true,
                  sortChoices: [
                    (
                      value: ProductSortField.relevance,
                      label: l10n.sortRelevance,
                    ),
                    (
                      value: ProductSortField.priceAsc,
                      label: l10n.sortLowestPrice,
                    ),
                    (
                      value: ProductSortField.priceDesc,
                      label: l10n.sortHighestPrice,
                    ),
                  ],
                  initialSort: ProductSortField.relevance,
                  resultCount: 12,
                  storeNames: {
                    '12': locale == 'ar' ? 'ميا كو' : 'MIA CO',
                    '9': 'ENARA',
                    '7': locale == 'ar' ? 'متجر لولي' : 'loly store',
                    '21': locale == 'ar'
                        ? 'المستقبل لمواد البناء'
                        : 'Future Building Materials',
                  },
                  showHandle: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'audit_11_filters_$locale');
      });
      expect(find.text(l10n.filterShowResults(12)), findsOneWidget);
      expect(find.text(l10n.filterSortByLabel), findsOneWidget);
      expect(find.text(l10n.filterStoreLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the sort sheet renders in $locale', (tester) async {
      _surface(tester);
      final key = GlobalKey();
      await withRealShadows(() async {
        await tester.pumpWidget(
          _app(
            key,
            locale: locale,
            router: _router(
              open: true,
              _sheetHost(
                (context) => const SortSheet(
                  current: ProductSortField.priceAsc,
                  showHandle: true,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'audit_11_sort_$locale');
      });
      expect(find.text(l10n.sortLowestPrice), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
