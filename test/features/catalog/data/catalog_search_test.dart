import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_client.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_search.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_search.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/domain/search_results.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';

/// The GraphQL catalogue, recording what the fallback asked.
class _Catalog extends FakeCatalogRepository {
  _Catalog()
    : super(
        products: const [
          Product(
            sku: 'sofabed123',
            name: 'Corner Sofa Bed',
            urlKey: 'sofabed123',
            finalPrice: Money(amount: 425, currency: 'AED'),
            typeId: 'configurable',
          ),
        ],
        aggregations: const <Aggregation>[],
      );

  final List<
    ({Map<String, Set<String>> filters, ProductSortField sort, int page})
  >
  calls = [];

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
    calls.add((filters: attributeFilters, sort: sort, page: currentPage));
    return super.fetchProducts(search: search, currentPage: currentPage);
  }
}

CatalogSearch _search(FakeAlgoliaBackend backend, _Catalog catalog) =>
    CatalogSearch(
      algolia: AlgoliaSearch(
        client: AlgoliaClient(backend.client),
        settings: AlgoliaSettingsRepository(
          config: AppConfig.current,
          client: backend.client,
          cache: FakeLocalCache(),
          storefrontPage: (store) =>
              Uri.parse('https://hub-market.magento2.click/$store/'),
        ),
      ),
      catalog: catalog,
    );

void main() {
  test('Algolia answers first, and nothing reaches GraphQL', () async {
    final catalog = _Catalog();
    final search = _search(FakeAlgoliaBackend(), catalog);

    final result = await search.typeAhead(storeCode: 'en', query: 'sofa');

    expect(result.engine, SearchEngine.algolia);
    expect(catalog.calls, isEmpty);
  });

  test('without Algolia the type-ahead falls back to GraphQL', () async {
    final catalog = _Catalog();
    // The storefront page is down, so there is no key.
    final search = _search(FakeAlgoliaBackend(pageStatus: 503), catalog);

    final result = await search.typeAhead(storeCode: 'en', query: 'sofa');

    expect(result.engine, SearchEngine.catalog);
    expect(result.products.single.product.name, 'Corner Sofa Bed');
    // Highlighted locally, word by word.
    expect(result.products.single.nameMatches, [(start: 7, end: 11)]);
    expect(result.pages, isEmpty);
    expect(catalog.calls, hasLength(1));
  });

  test(
    'a fallback results page drops Algolia\'s filters but keeps a price sort',
    () async {
      final catalog = _Catalog();
      final search = _search(FakeAlgoliaBackend(algoliaStatus: 500), catalog);

      final page = await search.results(
        storeCode: 'en',
        query: 'sofa',
        filters: const SearchFilters(
          attributes: {
            'color': {'Pink'},
          },
        ),
        sort: const SearchSort('price', descending: true),
      );

      expect(page.engine, SearchEngine.catalog);
      expect(page.filters.isEmpty, isTrue);
      expect(page.sort, const SearchSort('price', descending: true));
      expect(catalog.calls.single.filters, isEmpty);
      expect(catalog.calls.single.sort, ProductSortField.priceDesc);
      expect(page.sorts.map((o) => o.sort), [
        SearchSort.relevance,
        const SearchSort('price'),
        const SearchSort('price', descending: true),
        const SearchSort('name'),
      ]);
      // "Newest first" is an Algolia replica; GraphQL can't sort by it.
      final newest = await search.results(
        storeCode: 'en',
        query: 'sofa',
        sort: const SearchSort('created_at', descending: true),
      );
      expect(newest.sort, SearchSort.relevance);
    },
  );

  test('later pages of an Algolia list never switch engines', () async {
    final catalog = _Catalog();
    final search = _search(FakeAlgoliaBackend(algoliaStatus: 500), catalog);

    await expectLater(
      search.results(
        storeCode: 'en',
        query: 'sofa',
        page: 2,
        engine: SearchEngine.algolia,
      ),
      throwsA(isA<AlgoliaUnavailable>()),
    );
    expect(catalog.calls, isEmpty);

    // A GraphQL list keeps its filters on later pages.
    await search.results(
      storeCode: 'en',
      query: 'sofa',
      page: 2,
      engine: SearchEngine.catalog,
      filters: const SearchFilters(
        attributes: {
          'category_uid': {'NzQ='},
        },
      ),
    );
    expect(catalog.calls.single.filters, {
      'category_uid': {'NzQ='},
    });
    expect(catalog.calls.single.page, 2);
  });
}
