import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_client.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_hits.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_search.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/search_highlight.dart';
import 'package:hubmarket_app/features/catalog/domain/search_results.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';

final _settings = AlgoliaSettings.fromStorefrontConfig(
  storefrontAlgoliaConfig(),
);
final _now = DateTime.utc(2026, 9, 29, 16);

// The live tree's furniture branch (ids 74 / 75 / 76), plus a hidden one.
const _tree = <Category>[
  Category(
    uid: 'NzQ=',
    name: 'Furniture',
    urlKey: 'furniture',
    productCount: 7,
    children: [
      Category(uid: 'NzU=', name: 'Home Furniture', urlKey: 'home-furniture'),
      Category(
        uid: 'NzY=',
        name: 'Office Furniture',
        urlKey: 'office-furniture',
      ),
      Category(uid: 'MTY4', name: 'All', urlKey: 'all', includeInMenu: false),
    ],
  ),
];

Map<String, dynamic> _sofaBed() => productRecord(
  id: '2096',
  name: 'Corner Sofa Bed',
  urlKey: 'sofabed123',
  sku: ['sofabed123', 'sofabed123-grey', 'sofabed123-turquoise'],
  type: 'configurable',
  price: 425,
  original: 'AED\u00A0500',
  categoryPaths: ['Furniture', 'Furniture /// Home Furniture'],
  categoryIds: ['74', '75'],
  highlighted: 'Corner ${kHighlightPreTag}Sofa$kHighlightPostTag Bed',
);

void main() {
  group('hits', () {
    test('a product record: url_key from its URL, first SKU, type, prices', () {
      final product = productFromAlgoliaHit(_sofaBed(), _settings, now: _now)!;
      expect(product.urlKey, 'sofabed123');
      expect(product.sku, 'sofabed123');
      expect(product.typeId, 'configurable');
      expect(product.requiresOptions, isTrue);
      expect(product.finalPrice!.formatted(), 'AED 425.00');
      expect(product.regularPrice!.formatted(), 'AED 500.00');
      expect(product.isOnSale, isTrue);
      expect(product.discountPercent, 15);
      expect(product.imageUrl, endsWith('/cache/big/sofabed123.jpg'));
      expect(product.thumbnail, endsWith('/cache/small/sofabed123.jpg'));
    });

    test('a simple product with no special price', () {
      final product = productFromAlgoliaHit(
        productRecord(
          id: '1',
          name: 'Joust Duffle Bag',
          urlKey: 'joust-duffle-bag',
          sku: '24-MB01',
          price: 34,
        ),
        _settings,
        now: _now,
      )!;
      expect(product.sku, '24-MB01');
      expect(product.requiresOptions, isFalse);
      expect(product.isOnSale, isFalse);
      expect(product.finalPrice!.amount, 34);
    });

    test('a special price whose dates have passed shows the regular price', () {
      final product = productFromAlgoliaHit(
        productRecord(
          id: '1',
          name: 'Joust Duffle Bag',
          urlKey: 'joust-duffle-bag',
          price: 28.9,
          original: 'AED\u00A034',
          // Ended the day before.
          specialTo: _now.millisecondsSinceEpoch ~/ 1000 - 86400,
        ),
        _settings,
        now: _now,
      )!;
      expect(product.finalPrice!.amount, 34);
      expect(product.isOnSale, isFalse);
    });

    test('the average rating comes along; the records carry no count', () {
      final rated = productFromAlgoliaHit(
        _sofaBed()..['rating_summary'] = 94,
        _settings,
        now: _now,
      )!;
      expect(rated.starRating, closeTo(4.7, 1e-9));
      expect(rated.reviewCount, isNull);
      final unrated = productFromAlgoliaHit(
        _sofaBed()..['rating_summary'] = 0,
        _settings,
        now: _now,
      )!;
      expect(unrated.starRating, isNull);
      expect(
        productFromAlgoliaHit(_sofaBed(), _settings, now: _now)!.starRating,
        isNull,
      );
    });

    test('the seller comes along only while the cards show sellers', () {
      final record = _sofaBed()
        ..['seller'] = 'MIA CO'
        ..['seller_id'] = 12
        ..['seller_url_key'] = 'MIA';

      final shown = productFromAlgoliaHit(
        record,
        _settings,
        now: _now,
        sellers: true,
      )!;
      expect(shown.sellerKnown, isTrue);
      expect(shown.sellerName, 'MIA CO');
      expect(shown.sellerCode, 'MIA');

      // Hub Market's own product: no seller on the record, an empty line.
      final own = productFromAlgoliaHit(
        _sofaBed(),
        _settings,
        now: _now,
        sellers: true,
      )!;
      expect(own.sellerKnown, isTrue);
      expect(own.sellerName, isNull);

      // Build 1: no seller line at all.
      final build1 = productFromAlgoliaHit(record, _settings, now: _now)!;
      expect(build1.sellerKnown, isFalse);
      expect(build1.sellerName, isNull);
    });

    test('a new_bundle record opens its page from the card', () {
      final product = productFromAlgoliaHit(
        productRecord(
          id: '2101',
          name: 'house tools',
          urlKey: 'house-tools',
          sku: 'house tools',
          type: 'new_bundle',
          price: 170,
        ),
        _settings,
        now: _now,
      )!;
      expect(product.typeId, 'new_bundle');
      expect(product.requiresOptions, isTrue);
    });

    test('a record with no product URL is skipped', () {
      final record = _sofaBed()
        ..['url'] = 'https://hub-market.magento2.click/en/';
      expect(productFromAlgoliaHit(record, _settings, now: _now), isNull);
    });

    test('formatted prices: Latin, Arabic and Arabic-Indic digits, ranges', () {
      expect(parseFormattedPrice('AED\u00A01,299'), 1299);
      expect(parseFormattedPrice('500\u00A0د.إ.\u200F'), 500);
      expect(
        parseFormattedPrice('\u0665\u0660\u0660\u066B\u0665\u0660 د.إ'),
        500.5,
      );
      expect(parseFormattedPrice('AED 425 - AED 500'), 425);
      expect(parseFormattedPrice(''), isNull);
      expect(parseFormattedPrice(null), isNull);
    });

    test(
      'the type-ahead row: Algolia\'s highlight and the deepest category',
      () {
        final row = productHitFromAlgolia(_sofaBed(), _settings, now: _now)!;
        expect(row.nameMatches, [(start: 7, end: 11)]);
        expect(row.product.name.substring(7, 11), 'Sofa');
        expect(row.categoryName, 'Home Furniture');
      },
    );

    test('a highlight that doesn\'t match the name is ignored', () {
      final record = _sofaBed()
        ..['_highlightResult'] = {
          'name': {'value': 'Other ${kHighlightPreTag}text$kHighlightPostTag'},
        };
      expect(
        productHitFromAlgolia(record, _settings, now: _now)!.nameMatches,
        isEmpty,
      );
    });

    test('categories and pages records', () {
      final category = categoryFromAlgoliaHit({
        'objectID': '75',
        'name': 'Home Furniture',
        'path': 'Furniture / Home Furniture',
        'level': 3,
        'product_count': 4,
      })!;
      expect(category.uid, 'NzU=');
      expect(category.name, 'Home Furniture');
      expect(category.count, 4);

      final page = pageFromAlgoliaHit({
        'objectID': '6',
        'name': 'Customer Service',
        'url': 'https://hub-market.magento2.click/en/customer-service',
      })!;
      expect(page.title, 'Customer Service');
      // The store's own home page is not a page to open.
      expect(
        pageFromAlgoliaHit({
          'name': 'Home',
          'url': 'https://hub-market.magento2.click/en/',
        }),
        isNull,
      );
    });
  });

  group('type-ahead', () {
    test('queries: products, categories and pages of the store view', () {
      final queries = typeAheadQueries(
        AlgoliaSettings.fromStorefrontConfig(
          storefrontAlgoliaConfig(store: 'ar'),
        ),
        query: 'كنبة',
        scopeUid: 'NzQ=',
      );
      expect(queries.map((q) => q.indexName), [
        'hubmarket_ar_products',
        'hubmarket_ar_categories',
        'hubmarket_ar_pages',
      ]);
      final products = queries.first.params;
      expect(products['query'], 'كنبة');
      expect(products['hitsPerPage'], 8);
      expect(products['facets'], ['categoryIds']);
      expect(products['numericFilters'], ['visibility_search=1']);
      expect(products['facetFilters'], ['categoryIds:74']);
      expect(products['attributesToHighlight'], ['name']);
      expect(products['highlightPreTag'], kHighlightPreTag);
      expect(queries[1].params['hitsPerPage'], 2);
      expect(queries[1].params['numericFilters'], ['include_in_menu=1']);
      expect(queries[2].params['hitsPerPage'], 2);
      expect(queries[2].params['attributesToSnippet'], isEmpty);
    });

    test('no pages section configured, no pages query', () {
      final settings = AlgoliaSettings.fromStorefrontConfig(
        storefrontAlgoliaConfig(pages: false),
      );
      final queries = typeAheadQueries(settings, query: 'sofa');
      expect(queries.map((q) => q.indexName), [
        'hubmarket_en_products',
        'hubmarket_en_categories',
      ]);
      final result = typeAheadFromResults(
        settings,
        [
          {
            'hits': [_sofaBed()],
            'nbHits': 34,
          },
          emptyResult(),
        ],
        query: 'sofa',
        now: _now,
      );
      expect(result.pages, isEmpty);
      expect(result.totalCount, 34);
    });

    test('the answer: rows, result categories from ids, chips, pages', () {
      final result = typeAheadFromResults(
        _settings,
        [
          {
            'hits': [_sofaBed()],
            'nbHits': 34,
            'facets': {
              'categoryIds': {'74': 3, '168': 3, '75': 2, '3': 30},
            },
          },
          {
            'hits': [
              {'objectID': '76', 'name': 'Office Furniture', 'level': 3},
            ],
          },
          {
            'hits': [
              {
                'objectID': '6',
                'name': 'Customer Service',
                'url': 'https://hub-market.magento2.click/en/customer-service',
              },
            ],
          },
        ],
        query: 'sofa',
        now: _now,
        tree: _tree,
      );

      expect(result.engine, SearchEngine.algolia);
      expect(result.totalCount, 34);
      expect(result.products.single.product.name, 'Corner Sofa Bed');
      // Named from the tree; the hidden "All" (168) and the unknown 3 go.
      expect(result.resultCategories.map((c) => (c.name, c.uid, c.count)), [
        ('Furniture', 'NzQ=', 3),
        ('Home Furniture', 'NzU=', 2),
      ]);
      expect(result.categoryChips.single.uid, 'NzY=');
      expect(result.pages.single.title, 'Customer Service');
    });
  });

  group('results', () {
    test('page, replica, facets, and OR-within / AND-across filters', () {
      final plan = resultsQueries(
        _settings,
        query: 'chair',
        scopeUid: 'NzQ=',
        filters: const SearchFilters(
          attributes: {
            'color': {'Pink', 'Teal'},
            kAlgoliaCategoryIds: {'75'},
          },
          priceFrom: 10,
          priceTo: 200,
          minRating: 3,
        ),
        sort: const SearchSort('created_at', descending: true),
        page: 3,
        hitsPerPage: 20,
      );

      final main = plan.queries.first;
      expect(main.indexName, 'hubmarket_en_products_created_at_desc');
      expect(main.params['page'], 2);
      expect(main.params['hitsPerPage'], 20);
      expect(main.params['facets'], [
        'categoryIds',
        'price.AED.default',
        'mgs_brand',
        'color',
        'seller',
      ]);
      expect(main.params['facetFilters'], [
        'categoryIds:74',
        ['color:Pink', 'color:Teal'],
        ['categoryIds:75'],
      ]);
      expect(main.params['numericFilters'], [
        'visibility_search=1',
        'price.AED.default>=10.0',
        'price.AED.default<=200.0',
        'rating_summary>=60',
      ]);

      // One count-only search per filtered facet, without its own filter.
      expect(plan.disjunctive, ['color', 'categoryIds', 'price.AED.default']);
      final color = plan.queries[1];
      expect(color.params['hitsPerPage'], 0);
      expect(color.params['facets'], ['color']);
      expect(color.params['facetFilters'], [
        'categoryIds:74',
        ['categoryIds:75'],
      ]);
      final price = plan.queries[3];
      expect(price.params['numericFilters'], [
        'visibility_search=1',
        'rating_summary>=60',
      ]);
    });

    test('relevance searches the primary index; facet values are escaped', () {
      final plan = resultsQueries(
        _settings,
        query: 'x',
        filters: const SearchFilters(
          attributes: {
            'mgs_brand': {'-Minus'},
          },
        ),
      );
      expect(plan.queries.first.indexName, 'hubmarket_en_products');
      expect(plan.queries.first.params['page'], 0);
      expect(plan.queries.first.params['facetFilters'], [
        ['mgs_brand:\\-Minus'],
      ]);
    });

    test('the page: products, sections, categories tab, sorts, paging', () {
      const filters = SearchFilters(
        attributes: {
          'color': {'Pink'},
        },
      );
      final plan = resultsQueries(_settings, query: 'chair', filters: filters);
      final page = resultsFromResponses(
        _settings,
        plan,
        [
          {
            'hits': [_sofaBed()],
            'nbHits': 41,
            'page': 1,
            'nbPages': 3,
            'facets': {
              'categoryIds': {'74': 2, '75': 1},
              'color': {'Pink': 1},
              'mgs_brand': {'MIA': 1},
            },
            'facets_stats': {
              'price.AED.default': {'min': 34.5, 'max': 180.2},
            },
          },
          {
            'hits': <Object>[],
            'nbHits': 4,
            'facets': {
              'color': {'Pink': 1, 'Teal': 2, 'Burgundy': 1},
            },
          },
        ],
        now: _now,
        filters: filters,
        tree: _tree,
      );

      expect(page.engine, SearchEngine.algolia);
      expect(page.totalCount, 41);
      expect(page.currentPage, 2);
      expect(page.totalPages, 3);
      expect(page.products.single.urlKey, 'sofabed123');
      expect(page.filters, same(filters));

      final sections = {for (final f in page.facets) f.attributeCode: f};
      expect(sections.keys, ['price', 'categoryIds', 'mgs_brand', 'color']);
      expect(sections['price']!.options.single.value, '34_181');
      expect(sections['categoryIds']!.label, 'Categories');
      expect(
        sections['categoryIds']!.options.map(
          (o) => (o.label, o.value, o.count),
        ),
        [('Furniture', '74', 2), ('Home Furniture', '75', 1)],
      );
      expect(sections['mgs_brand']!.label, 'Brand');
      // The filtered facet keeps its other values, from its own search.
      expect(sections['color']!.options.map((o) => o.value), [
        'Pink',
        'Teal',
        'Burgundy',
      ]);

      expect(page.categories.map((c) => c.name), [
        'Furniture',
        'Home Furniture',
      ]);
      expect(page.sorts.map((o) => (o.sort.attribute, o.sort.descending)), [
        ('', false),
        ('price', false),
        ('price', true),
        ('created_at', true),
      ]);
      expect(page.sorts[3].label, 'Newest first');
      expect(page.ratingFilter, isTrue);
    });
  });

  group('try suggestions (S2)', () {
    final withIndex = AlgoliaSettings.fromStorefrontConfig({
      ...storefrontAlgoliaConfig(),
      'autocomplete': {
        'nbOfProductsSuggestions': 8,
        'areSuggestionsEnabled': true,
        'showAlgoliaSuggestions': false,
        'nbOfQueriesSuggestions': 5,
      },
    });

    test('no suggestions index, no query: nothing is made up', () {
      expect(_settings.suggestionIndex, isNull);
      expect(trySuggestionsQuery(_settings, query: 'sofa bed'), isNull);
      expect(trySuggestionsQuery(withIndex, query: '  '), isNull);
    });

    test('asks the store\'s suggestions index, every word optional', () {
      final query = trySuggestionsQuery(withIndex, query: 'sofa bed velvet')!;
      expect(query.indexName, 'hubmarket_en_suggestions');
      expect(query.params['query'], 'sofa bed velvet');
      // Three shown, one more in case the query itself comes back.
      expect(query.params['hitsPerPage'], 4);
      expect(query.params['removeWordsIfNoResults'], 'allOptional');
      expect(query.params['attributesToRetrieve'], ['query']);
    });

    test('the answer: distinct queries, never the search itself', () {
      final terms = trySuggestionsFromResult(
        {
          'hits': [
            {'query': 'Sofa Bed Velvet'},
            {'query': 'sofa bed'},
            {'query': 'green sofa'},
            {'query': 'sofa bed'},
            {'query': ''},
            {'query': 'furniture'},
            {'query': 'bed frame'},
          ],
        },
        query: 'sofa bed velvet',
      );
      expect(terms, ['sofa bed', 'green sofa', 'furniture']);
    });

    test('a missing suggestions index answers nothing and never rests '
        'search', () async {
      final backend = FakeAlgoliaBackend(
        configs: {
          'en': {
            ...storefrontAlgoliaConfig(),
            'autocomplete': {
              'nbOfProductsSuggestions': 8,
              'nbOfCategoriesSuggestions': 2,
              'areSuggestionsEnabled': true,
              'showAlgoliaSuggestions': false,
              'nbOfQueriesSuggestions': 5,
            },
          },
        },
        answer: (query) => query.indexName == 'hubmarket_en_suggestions'
            ? {
                'hits': [
                  {'query': 'sofa bed'},
                  {'query': 'green sofa'},
                ],
              }
            : emptyResult(),
      );
      final search = AlgoliaSearch(
        client: AlgoliaClient(backend.client),
        settings: AlgoliaSettingsRepository(
          config: AppConfig.current,
          client: backend.client,
          cache: FakeLocalCache(),
          storefrontPage: (store) =>
              Uri.parse('https://hub-market.magento2.click/$store/'),
        ),
      );

      expect(
        await search.trySuggestions(storeCode: 'en', query: 'sofa velvet'),
        ['sofa bed', 'green sofa'],
      );

      backend.algoliaStatus = 404;
      expect(
        await search.trySuggestions(storeCode: 'en', query: 'sofa velvet'),
        isEmpty,
      );
      backend.algoliaStatus = 200;
      // Search itself carries on at once.
      await search.typeAhead(storeCode: 'en', query: 'sofa');
      expect(backend.lastCall.first.indexName, 'hubmarket_en_products');
    });
  });

  group('AlgoliaSearch', () {
    AppConfig config() => AppConfig.current;

    test('a refused key is replaced from the storefront once', () async {
      final backend = FakeAlgoliaBackend(algoliaStatus: 403);
      final settings = AlgoliaSettingsRepository(
        config: config(),
        client: backend.client,
        cache: FakeLocalCache(),
        storefrontPage: (store) =>
            Uri.parse('https://hub-market.magento2.click/$store/'),
      );
      final search = AlgoliaSearch(
        client: AlgoliaClient(backend.client),
        settings: settings,
      );

      await expectLater(
        search.typeAhead(storeCode: 'en', query: 'sofa'),
        throwsA(isA<AlgoliaUnavailable>()),
      );
      // The page again for a fresh key, then one more try.
      expect(backend.pageRequests, hasLength(2));
      expect(backend.algoliaRequests, hasLength(2));

      // Resting after the failure: no request at all.
      backend.algoliaStatus = 200;
      await expectLater(
        search.typeAhead(storeCode: 'en', query: 'sofa'),
        throwsA(isA<AlgoliaUnavailable>()),
      );
      expect(backend.algoliaRequests, hasLength(2));
    });

    test('answers with the store view\'s indices', () async {
      final backend = FakeAlgoliaBackend(
        answer: (query) => query.indexName.endsWith('_products')
            ? {
                'hits': [_sofaBed()],
                'nbHits': 1,
              }
            : emptyResult(),
      );
      final search = AlgoliaSearch(
        client: AlgoliaClient(backend.client),
        settings: AlgoliaSettingsRepository(
          config: config(),
          client: backend.client,
          cache: FakeLocalCache(),
          storefrontPage: (store) =>
              Uri.parse('https://hub-market.magento2.click/$store/'),
        ),
      );

      final result = await search.typeAhead(storeCode: 'ar', query: 'كنبة');

      expect(result.products.single.product.urlKey, 'sofabed123');
      expect(backend.lastCall.map((q) => q.indexName), [
        'hubmarket_ar_products',
        'hubmarket_ar_categories',
        'hubmarket_ar_pages',
      ]);
      final sent = backend.algoliaRequests.single;
      expect(sent.headers['X-Algolia-API-Key'], isNotEmpty);
    });
  });
}
