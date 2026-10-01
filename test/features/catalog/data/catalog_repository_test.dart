import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';

/// A client that records each request's variables and answers with [data].
///
/// `__typename` is present because graphql_flutter injects it into every
/// document and the normalizing cache rejects a response without it.
class _RecordingClient {
  _RecordingClient(this.data);

  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> variables = [];
  final List<String?> operations = [];

  GraphQLClient get client => GraphQLClient(
    link: Link.function((request, [forward]) {
      variables.add(request.variables);
      operations.add(
        request.operation.document.definitions
            .whereType<OperationDefinitionNode>()
            .first
            .name
            ?.value,
      );
      return Stream<Response>.value(
        Response(data: data, response: const {}, context: const Context()),
      );
    }),
    cache: GraphQLCache(),
  );
}

const Map<String, dynamic> _emptyPage = {
  '__typename': 'Query',
  'products': {
    '__typename': 'Products',
    'total_count': 0,
    'page_info': {
      '__typename': 'SearchResultPageInfo',
      'current_page': 1,
      'total_pages': 0,
      'page_size': 20,
    },
    'items': <dynamic>[],
    'aggregations': <dynamic>[],
  },
};

const Map<String, dynamic> _unresolved = {
  '__typename': 'Query',
  'urlResolver': null,
};


Map<String, dynamic> _node(
  String uid,
  String name,
  String key, {
  required int menu,
  required int products,
  List<Map<String, dynamic>>? children,
}) => {
  '__typename': 'CategoryTree',
  'uid': uid,
  'name': name,
  'url_key': key,
  'image': null,
  'include_in_menu': menu,
  'product_count': products,
  'children': ?children,
};

/// What Hub Market answers for Shoes (live, 1 Oct 2026): a category the admin
/// keeps out of the menu (include_in_menu 0) whose two children are in it, here
/// with a hidden one added.
Map<String, dynamic> _shoesAnswer() => {
  '__typename': 'Query',
  'categories': {
    '__typename': 'CategoryResult',
    'items': [
      _node(
        'NTM=',
        'Shoes',
        'shoes',
        menu: 0,
        products: 12,
        children: [
          _node('NTU=', 'Women', 'women', menu: 1, products: 6, children: []),
          _node('NTQ=', 'Men', 'men', menu: 1, products: 6, children: []),
          _node(
            'OTk=',
            'Archive',
            'archive',
            menu: 0,
            products: 0,
            children: [],
          ),
        ],
      ),
    ],
  },
};

void main() {
  group('CatalogRepository.fetchProducts on Hub Market', () {
    test('the brand landing filters on the mgs_brand attribute', () async {
      final recorder = _RecordingClient(_emptyPage);
      await CatalogRepository(recorder.client).fetchProducts(
        brandOptionId: 222,
      );

      expect(recorder.variables.single['filter'], {
        'mgs_brand': {'eq': '222'},
      });
    });

    test('discount / rating thresholds are never sent', () async {
      // Neither is a ProductAttributeFilterInput field on this store; sending
      // one makes Magento reject the whole products query.
      expect(kDiscountFilterSupported, isFalse);
      expect(kRatingFilterSupported, isFalse);

      final recorder = _RecordingClient(_emptyPage);
      await CatalogRepository(recorder.client).fetchProducts(
        categoryUid: 'MTAx',
        minDiscount: 30,
        minRating: 4,
      );

      expect(recorder.variables.single['filter'], {
        'category_uid': {'eq': 'MTAx'},
      });
    });
  });

  group('CatalogRepository.fetchProducts for search', () {
    const searchPage = {
      '__typename': 'Query',
      'products': {
        '__typename': 'Products',
        'total_count': 23,
        'page_info': {
          '__typename': 'SearchResultPageInfo',
          'current_page': 1,
          'total_pages': 2,
          'page_size': 20,
        },
        'items': [
          {
            '__typename': 'SimpleProduct',
            'sku': 'bag-1',
            'name': 'Square Shoulder Bag',
            'url_key': 'square-shoulder-bag',
            'stock_status': 'IN_STOCK',
            'new_from_date': null,
            'new_to_date': null,
            'rating_summary': 87,
            'review_count': 3,
            'image': null,
            'price_range': null,
            'categories': [
              {
                '__typename': 'CategoryTree',
                'uid': 'MTI5',
                'name': 'Bags',
                'level': 2,
                'include_in_menu': 0,
              },
              {
                '__typename': 'CategoryTree',
                'uid': 'MTMw',
                'name': "Women's Bags",
                'level': 3,
                'include_in_menu': 1,
              },
            ],
          },
        ],
        'aggregations': [
          {
            '__typename': 'Aggregation',
            'attribute_code': 'category_uid',
            'label': 'Category',
            'options': [
              {
                '__typename': 'AggregationOption',
                'label': "Women's Bags",
                'value': 'MTMw',
                'count': 12,
              },
            ],
          },
        ],
      },
    };

    test('a search asks for each hit\'s categories', () async {
      final recorder = _RecordingClient(searchPage);
      final page = await CatalogRepository(recorder.client).fetchProducts(
        search: 'bag',
        categoryUid: 'MTI5',
      );

      expect(recorder.operations.single, 'SearchProducts');
      expect(recorder.variables.single['search'], 'bag');
      expect(recorder.variables.single['filter'], {
        'category_uid': {'eq': 'MTI5'},
      });
      expect(page.totalCount, 23);
      expect(page.items.single.primaryCategory?.name, "Women's Bags");
      // The card's stars (Figma v3) ride along with every listing.
      expect(page.items.single.reviewCount, 3);
      expect(page.items.single.starRating, closeTo(4.35, 1e-9));
      expect(page.aggregations.single.options.single.count, 12);
    });

    test('a plain listing keeps the lighter Products document', () async {
      final recorder = _RecordingClient(_emptyPage);
      await CatalogRepository(recorder.client).fetchProducts(
        categoryUid: 'MTAx',
      );

      expect(recorder.operations.single, 'Products');
    });
  });

  group('CatalogRepository.resolveUrl', () {
    Future<String?> resolvedPath(String url) async {
      final recorder = _RecordingClient(_unresolved);
      await CatalogRepository(recorder.client).resolveUrl(url);
      return recorder.variables.isEmpty
          ? null
          : recorder.variables.single['url'] as String?;
    }

    test("strips Hub Market's en / ar store segment", () async {
      // urlResolver answers null for `en/abominable-hoodie.html`.
      expect(
        await resolvedPath(
          'https://hub-market.magento2.click/en/abominable-hoodie.html',
        ),
        'abominable-hoodie.html',
      );
      expect(
        await resolvedPath(
          'https://hub-market.magento2.click/ar/fashion/women.html',
        ),
        'fashion/women.html',
      );
    });

    test('still strips uae-en style store codes', () async {
      expect(
        await resolvedPath('https://example.com/uae-en/foo.html'),
        'foo.html',
      );
    });

    test('a path with no store segment passes through', () async {
      expect(
        await resolvedPath(
          'https://hub-market.magento2.click/abominable-hoodie.html',
        ),
        'abominable-hoodie.html',
      );
    });
  });

  group('CatalogRepository.fetchCategoryByUid', () {
    test(
      'asks for the one uid and maps a category the menu leaves out',
      () async {
        final recorder = _RecordingClient(_shoesAnswer());
        final shoes = await CatalogRepository(
          recorder.client,
        ).fetchCategoryByUid('NTM=');

        expect(recorder.operations, ['CategoryByUid']);
        expect(recorder.variables.single, {'uid': 'NTM='});
        expect(shoes, isNotNull);
        expect(shoes!.uid, 'NTM=');
        expect(shoes.name, 'Shoes');
        expect(shoes.urlKey, 'shoes');
        expect(shoes.productCount, 12);
        // include_in_menu comes back as the Int 0: why it is fetched here.
        expect(shoes.includeInMenu, isFalse);
      },
    );

    test(
      'keeps the children and their menu flags, for the caller to filter',
      () async {
        final recorder = _RecordingClient(_shoesAnswer());
        final shoes = await CatalogRepository(
          recorder.client,
        ).fetchCategoryByUid('NTM=');

        expect(shoes!.children.map((c) => c.name), [
          'Women',
          'Men',
          'Archive',
        ]);
        expect(shoes.children.map((c) => c.includeInMenu), [
          true,
          true,
          false,
        ]);
      },
    );

    test('is null when no category has that uid', () async {
      final recorder = _RecordingClient({
        '__typename': 'Query',
        'categories': {'__typename': 'CategoryResult', 'items': <dynamic>[]},
      });
      expect(
        await CatalogRepository(
          recorder.client,
        ).fetchCategoryByUid('Tm9wZQ=='),
        isNull,
      );
    });

    test('sends nothing for a blank uid', () async {
      final recorder = _RecordingClient(_shoesAnswer());
      final repository = CatalogRepository(recorder.client);
      expect(await repository.fetchCategoryByUid(''), isNull);
      expect(await repository.fetchCategoryByUid('  '), isNull);
      expect(recorder.operations, isEmpty);
    });
  });
}
