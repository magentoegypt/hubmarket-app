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
import 'package:hubmarket_app/features/catalog/data/brands_provider.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/brand_page_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/brands_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';

Brand _brand(int id, String name, {int? option}) => Brand(
  brandId: id,
  title: name,
  urlKey: name.toLowerCase(),
  url: 'https://hub-market.magento2.click/en/brand/${name.toLowerCase()}.html',
  imageUrl: '',
  optionId: option ?? 200 + id,
  position: id,
);

final _brands = <Brand>[
  _brand(1, 'Samsung'),
  _brand(2, 'HP'),
  _brand(3, 'Fresh'),
  _brand(4, 'Acer'),
  _brand(5, 'Lenovo'),
  _brand(6, 'Kodak'), // no products → not listed
];

const _counts = <int, int>{201: 12, 202: 2, 203: 2, 204: 1, 205: 1, 206: 0};

/// Samsung's products, answering the mgs_brand filter like OpenSearch does.
class _BrandCatalog extends FakeCatalogRepository {
  final List<Map<String, Set<String>>> filters = [];

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
    filters.add(attributeFilters);
    final tvsOnly = attributeFilters['category_uid']?.contains('dHY=') ?? false;
    final items = [
      const Product(
        sku: 'tv',
        name: 'Samsung 65-Inch Television',
        urlKey: 'samsung-65',
        regularPrice: Money(amount: 1500, currency: 'AED'),
        finalPrice: Money(amount: 1275, currency: 'AED'),
      ),
      if (!tvsOnly)
        const Product(
          sku: 'a23',
          name: 'Samsung Galaxy A23',
          urlKey: 'galaxy-a23',
          regularPrice: Money(amount: 1200, currency: 'AED'),
          finalPrice: Money(amount: 1200, currency: 'AED'),
        ),
    ];
    return ProductPage(
      items: items,
      totalCount: items.length,
      currentPage: 1,
      totalPages: 1,
      aggregations: const [
        Aggregation(
          attributeCode: 'category_uid',
          label: 'Category',
          options: [
            AggregationOption(label: 'All', value: 'YWxs', count: 2),
            AggregationOption(label: 'Mobiles', value: 'bW9i', count: 1),
            AggregationOption(label: 'TVs', value: 'dHY=', count: 1),
          ],
        ),
      ],
    );
  }
}

final _visited = <String>[];

Widget _harness(
  Widget screen, {
  String locale = 'en',
  GlobalKey? boundary,
  _BrandCatalog? catalog,
  int? sellers = 2,
}) {
  _visited.clear();
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
        '/search',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
      GoRoute(
        path: '/brand/:urlKey',
        builder: (_, s) {
          _visited.add(s.uri.toString());
          return Scaffold(body: Text('brand ${s.pathParameters['urlKey']}'));
        },
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
      brandsProvider.overrideWith((ref) async => _brands),
      brandProductCountsProvider.overrideWith((ref) async => _counts),
      brandSellerCountProvider.overrideWith((ref, id) async => sellers),
      catalogRepositoryProvider.overrideWithValue(catalog ?? _BrandCatalog()),
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

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  group('All brands (10d)', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('brands with products, A–Z, counts ($locale)', (
        tester,
      ) async {
        await _phone(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          _harness(const BrandsScreen(), locale: locale, boundary: key),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'brands_$locale');

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BrandsScreen)),
        );
        expect(find.text(l10n.brandsWithProducts(5)), findsOneWidget);
        expect(find.text('Kodak'), findsNothing);
        expect(find.text(l10n.hmProductCount(12)), findsOneWidget);
        // The hint names the first brands, not a hard-coded list.
        expect(find.text('Samsung, HP, Fresh…'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('search, initials, and a card opens the brand page', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(const BrandsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('H'));
      await tester.pumpAndSettle();
      expect(find.text('HP'), findsOneWidget);
      expect(find.text('Samsung'), findsNothing);

      await tester.tap(find.text('All'));
      await tester.enterText(find.byType(TextField), 'len');
      await tester.pumpAndSettle();
      expect(find.text('Lenovo'), findsOneWidget);
      expect(find.text('Acer'), findsNothing);

      await tester.tap(find.text('Lenovo'));
      await tester.pumpAndSettle();
      expect(_visited, ['/brand/lenovo']);
    });
  });

  group('Brand page (10e)', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('header, category chips, sort and grid ($locale)', (
        tester,
      ) async {
        await _phone(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          _harness(
            BrandPageScreen(urlKey: 'samsung', brand: _brands.first),
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'brand_page_$locale');

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BrandPageScreen)),
        );
        expect(find.text('Samsung'), findsWidgets);
        expect(
          find.text('${l10n.hmProductCount(2)} · ${l10n.brandFromStores(2)}'),
          findsOneWidget,
        );
        // "All" is a category every product is in: no chip for it.
        expect(find.text('Mobiles'), findsOneWidget);
        expect(find.text('TVs'), findsOneWidget);
        expect(find.text('Samsung Galaxy A23'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a chip filters on the category', (tester) async {
      await _phone(tester);
      final catalog = _BrandCatalog();
      await tester.pumpWidget(
        _harness(
          BrandPageScreen(urlKey: 'samsung', brand: _brands.first),
          catalog: catalog,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('TVs'));
      await tester.pumpAndSettle();

      expect(catalog.filters.last['category_uid'], {'dHY='});
      expect(find.text('Samsung Galaxy A23'), findsNothing);
    });

    testWidgets('found by url_key when opened from a link', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(const BrandPageScreen(urlKey: 'SAMSUNG'), sellers: null),
      );
      await tester.pumpAndSettle();
      expect(find.text('Samsung 65-Inch Television'), findsOneWidget);
      // No seller count: the products alone.
      expect(find.text('2 products'), findsWidgets);
    });

    testWidgets('an unknown brand shows the empty state', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(_harness(const BrandPageScreen(urlKey: 'nokia')));
      await tester.pumpAndSettle();
      expect(find.text('No brands found'), findsOneWidget);
    });
  });
}
