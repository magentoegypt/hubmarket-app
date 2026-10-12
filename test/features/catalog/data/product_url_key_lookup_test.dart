import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_queries.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_mapper.dart';
import 'package:hubmarket_app/features/catalog/data/product_marketplace_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_route_query.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';

import '../../../support/bundle_fixtures.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/marketplace_fakes.dart';

// Opening the Bose headphones from a search showed the "Gaming Set" bundle. The
// store's search index folds a bundle's options into the bundle, so the url_key
// of an option answers the bundle too, and the bundle can come first. Live on
// 12 Oct 2026, for `products(filter: {url_key: {eq: "bose-700"}})`:
//
//   [ BundleProduct "Gaming Set" (gaming-set), SimpleProduct "Bose 700" (bose-700) ]
//
// The app read one item, the first.

Map<String, dynamic> _gamingSet() => {
  '__typename': 'BundleProduct',
  'sku': 'Gaming Set',
  'name': 'Gaming Set',
  'url_key': 'gaming-set',
  'stock_status': 'IN_STOCK',
};

Map<String, dynamic> _bose() => {
  '__typename': 'SimpleProduct',
  'sku': '794297-0100',
  'name': 'Bose 700 Noise Cancelling Headphones, Bluetooth, Wireless, Mic',
  'url_key': 'bose-700',
  'stock_status': 'IN_STOCK',
};

Map<String, dynamic> _products(List<Map<String, dynamic>> items) => {
  'products': {'items': items},
};

void main() {
  group('productWithUrlKey', () {
    test('the product with the key, though a bundle that offers it is first', () {
      final found = productWithUrlKey([_gamingSet(), _bose()], 'bose-700');
      expect(found!['sku'], '794297-0100');
    });

    test('and when it is first', () {
      final found = productWithUrlKey([_bose(), _gamingSet()], 'bose-700');
      expect(found!['sku'], '794297-0100');
    });

    test('the bundle itself, by its own key', () {
      final found = productWithUrlKey([_gamingSet(), _bose()], 'gaming-set');
      expect(found!['sku'], 'Gaming Set');
    });

    test('keys are compared as the store writes them', () {
      expect(
        productWithUrlKey([_gamingSet(), _bose()], '  BOSE-700 ')!['sku'],
        '794297-0100',
      );
      // An Arabic key arrives percent-encoded from a link, decoded from the store.
      final tank = {'sku': 'TANK', 'url_key': 'تانك-توب'};
      expect(
        productWithUrlKey([_gamingSet(), tank], '%D8%AA%D8%A7%D9%86%D9%83-%D8%AA%D9%88%D8%A8')!['sku'],
        'TANK',
      );
    });

    test('a bad escape in the key is compared as written, not thrown', () {
      final odd = {'sku': 'ODD', 'url_key': '100%'};
      expect(productWithUrlKey([_gamingSet(), odd], '100%')!['sku'], 'ODD');
    });

    test('a single item is taken as it is, even if its key is spelt differently', () {
      final lone = {'sku': 'LONE', 'url_key': 'lone-product'};
      expect(productWithUrlKey([lone], 'Lone_Product')!['sku'], 'LONE');
    });

    test('several items and none with the key: nothing', () {
      expect(productWithUrlKey([_gamingSet(), _bose()], 'no-such-key'), isNull);
    });

    test('nothing to read, nothing found', () {
      expect(productWithUrlKey(null, 'bose-700'), isNull);
      expect(productWithUrlKey('not a list', 'bose-700'), isNull);
      expect(productWithUrlKey(const [], 'bose-700'), isNull);
      expect(productWithUrlKey(['text', 42, null, _bose()], 'bose-700')!['sku'], '794297-0100');
    });
  });

  group('the lookups ask for more than one product', () {
    final lookups = <String, String>{
      'ProductDetail': CatalogQueries.productDetail,
      'HmProductMarketplace': ProductMarketplaceQueries.productMarketplace,
      'HmProductMarketplaceSellers':
          ProductMarketplaceQueries.productMarketplaceSellers,
      'ProductReviews': ReviewQueries.productReviews,
    };

    lookups.forEach((name, document) {
      test('$name: a page of $kUrlKeyLookupPageSize, not 1', () {
        expect(
          document,
          contains(
            'products(filter: { url_key: { eq: \$urlKey } }, '
            'pageSize: $kUrlKeyLookupPageSize)',
          ),
        );
      });
    });

    test('the extras select the url_key they are picked by', () {
      for (final document in [
        ProductMarketplaceQueries.productMarketplace,
        ProductMarketplaceQueries.productMarketplaceSellers,
      ]) {
        expect(document, matches(RegExp(r'items \{\s+url_key\b')));
      }
    });

    test('the codegen mirror of the detail query says the same', () {
      final mirror = File(
        'lib/features/catalog/data/graphql/product_detail.graphql',
      ).readAsStringSync();
      expect(mirror, contains('pageSize: $kUrlKeyLookupPageSize)'));
    });

    test('the by-route query is still derived from the detail query', () {
      final route = productDetailByRouteOf(CatalogQueries.productDetail);
      expect(route, contains('route(url: \$url)'));
      // The page's head was swapped for the route: no product lookup is left.
      expect(route, isNot(contains('products(filter')));
    });

    test('no lookup by url_key in the app asks for a single product again', () {
      final stale = <String>[];
      final pattern = RegExp(
        r'url_key:\s*\{\s*eq:[^}]*\}\s*\}\s*,\s*pageSize:\s*1\s*\)',
      );
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.endsWith('.graphql.dart')) continue;
        if (!path.endsWith('.dart') && !path.endsWith('.graphql')) continue;
        if (pattern.hasMatch(entity.readAsStringSync())) stale.add(path);
      }
      expect(stale, isEmpty);
    });
  });

  group('CatalogRepository.fetchProductDetail', () {
    CatalogRepository repository(FakeHubAppClient client) =>
        CatalogRepository(client);

    test('opens the product, not the bundle that comes first', () async {
      final server = fakeHubAppClient({
        'ProductDetail': _products([_gamingSet(), _bose()]),
      });

      final detail = await repository(server).fetchProductDetail('bose-700');

      expect(detail!.sku, '794297-0100');
      expect(detail.urlKey, 'bose-700');
      expect(detail.typeId, 'simple');
      expect(detail.isBundle, isFalse);
      expect(server.requests.single.variables, {'urlKey': 'bose-700'});
    });

    test('the bundle still opens by its own key', () async {
      final server = fakeHubAppClient({
        'ProductDetail': _products([_gamingSet(), _bose()]),
      });

      final detail = await repository(server).fetchProductDetail('gaming-set');

      expect(detail!.sku, 'Gaming Set');
      expect(detail.isBundle, isTrue);
    });

    test('a key nobody has is not found', () async {
      final none = fakeHubAppClient({'ProductDetail': _products(const [])});
      expect(await repository(none).fetchProductDetail('nope'), isNull);

      final others = fakeHubAppClient({
        'ProductDetail': _products([_gamingSet(), _bose()]),
      });
      expect(await repository(others).fetchProductDetail('nope'), isNull);
    });
  });

  group('ProductMarketplaceRepository.fetch', () {
    // The extras HubApp answers: the bundle's options, then the product's seller.
    Map<String, dynamic> bundleExtras() => {
      ...fitnessPackJson(),
      'url_key': 'gaming-set',
    };
    Map<String, dynamic> boseExtras() => {
      '__typename': 'SimpleProduct',
      'sku': '794297-0100',
      'url_key': 'bose-700',
      'hm_seller': sellerJson('hassan1', 'Hassan1'),
    };

    test('the product\'s seller and no bundle, though the bundle is first', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': _products([bundleExtras(), boseExtras()]),
      });

      final extras = await ProductMarketplaceRepository(server).fetch('bose-700');

      expect(extras!.seller!.name, 'Hassan1');
      expect(extras.bundle, isNull);
      expect(server.requests, hasLength(1));
    });

    test('the same without the offers (an older HubAppVendors)', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplaceSellers': _products([bundleExtras(), boseExtras()]),
      });

      final extras = await ProductMarketplaceRepository(server).fetch(
        'bose-700',
        withOffers: false,
      );

      expect(extras!.seller!.name, 'Hassan1');
      expect(extras.bundle, isNull);
    });

    test('the bundle keeps its options by its own key', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': _products([bundleExtras(), boseExtras()]),
      });

      final extras = await ProductMarketplaceRepository(server).fetch('gaming-set');

      expect(extras!.bundle, isNotNull);
      expect(extras.seller!.name, 'Test 1');
    });

    test('no item with the key among several: the page by its address, as an offer', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': _products([bundleExtras()..['url_key'] = 'a', boseExtras()..['url_key'] = 'b']),
        'HmProductMarketplaceByRoute': {'route': boseExtras()},
      });

      final extras = await ProductMarketplaceRepository(server).fetch('offer-9');

      expect(extras!.seller!.name, 'Hassan1');
      expect(server.requests, hasLength(2));
    });
  });

  group('ReviewsRepository.fetchProductReviews', () {
    Map<String, dynamic> withReviews(Map<String, dynamic> product, int count) => {
      ...product,
      'rating_summary': 80,
      'review_count': count,
      'reviews': {
        'items': [
          for (var i = 0; i < count; i++)
            {
              'nickname': 'Sara',
              'summary': 'Review $i',
              'text': 'Fine',
              'average_rating': 80,
              'created_at': '2026-10-0${i + 1} 10:00:00',
            },
        ],
        'page_info': {'current_page': 1, 'page_size': 20, 'total_pages': 1},
      },
    };

    test('the reviews of the product, not of the bundle that comes first', () async {
      final server = fakeHubAppClient({
        'ProductReviews': _products([
          withReviews(_gamingSet(), 1),
          withReviews(_bose(), 2),
        ]),
      });

      final page = await ReviewsRepository(server).fetchProductReviews('bose-700');

      expect(page!.sku, '794297-0100');
      expect(page.reviewCount, 2);
      expect(page.reviews, hasLength(2));
    });

    test('a key nobody has has no reviews page', () async {
      final server = fakeHubAppClient({
        'ProductReviews': _products([withReviews(_gamingSet(), 1)]),
      });
      // A lone item is taken as it is, so ask for something with two.
      final two = fakeHubAppClient({
        'ProductReviews': _products([withReviews(_gamingSet(), 1), withReviews(_bose(), 2)]),
      });

      expect(await ReviewsRepository(two).fetchProductReviews('nope'), isNull);
      expect(server.requests, isEmpty);
    });
  });
}
