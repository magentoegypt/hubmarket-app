import 'package:flutter_test/flutter_test.dart';
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

  GraphQLClient get client => GraphQLClient(
    link: Link.function((request, [forward]) {
      variables.add(request.variables);
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

void main() {
  group('CatalogRepository.fetchProducts on Hub Market', () {
    test('the brand landing filters on the mgs_brand attribute', () async {
      final recorder = _RecordingClient(_emptyPage);
      await CatalogRepository(recorder.client).fetchProducts(
        manufacturerId: 222,
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
}
