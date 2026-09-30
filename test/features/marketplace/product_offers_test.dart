import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gql/language.dart' as gql_lang;
import 'package:gql/ast.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_queries.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_marketplace_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_route_query.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/marketplace/domain/product_offer.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';
import 'package:hubmarket_app/features/marketplace/product_offers.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';

/// An `HmProductOffer` as the backend serves it (the live Joust Duffle Bag
/// family of 30 Sep 2026).
Map<String, dynamic> offerJson(
  int id,
  String code,
  String name, {
  required double price,
  double? regular,
  String type = 'simple',
  Map<String, dynamic>? dispatch,
  double? rating,
}) => {
  '__typename': 'HmProductOffer',
  'uid': 'uid-$id',
  'sku': 'SKU-$id',
  'url_key': 'offer-$id',
  'type_id': type,
  'seller': sellerJson(code, name, rating: rating),
  'price': {'value': price, 'currency': 'AED'},
  'regular_price': {'value': regular ?? price, 'currency': 'AED'},
  'stock_status': 'IN_STOCK',
  'dispatch_time': dispatch,
};

/// The main product with its two offers, cheapest first.
Map<String, dynamic> duffleJson({int? count = 2, List<Object?>? offers}) => {
  '__typename': 'SimpleProduct',
  'sku': '24-MB01',
  'hm_seller': sellerJson('test_1', 'Test 1'),
  'hm_offer_count': count,
  'hm_other_offers':
      offers ??
      [
        offerJson(
          2287,
          'ENARA',
          'ENARA',
          price: 34,
          dispatch: {'code': 'days_2_3', 'label': '2-3 days', 'source': 'DECLARED'},
          rating: 4.4,
        ),
        offerJson(2150, 'hassan1', 'Hassan Store', price: 40, regular: 45),
      ],
};

Map<String, Object> _products(Map<String, dynamic>? item) => {
  'HmProductMarketplace': {
    'products': {
      'items': [?item],
    },
  },
};

/// A catalogue that knows the product page of [known] url keys only.
class _Catalog extends FakeCatalogRepository {
  _Catalog(this.known);
  final Map<String, ProductDetail> known;
  final List<String> asked = [];

  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async {
    asked.add(urlKey);
    return known[urlKey];
  }
}

/// A [ProductRouteRepository] answering from [pages] by URL.
class _Routes extends ProductRouteRepository {
  _Routes(this.pages, {this.fail = false}) : super(fakeGraphQLClient());
  final Map<String, ProductDetail> pages;
  final bool fail;
  final List<String> asked = [];

  @override
  Future<ProductDetail?> fetchDetail(String url) async {
    asked.add(url);
    if (fail) throw const Failure(FailureKind.network);
    return pages[url];
  }
}

ProductDetail _page(String sku, String urlKey) => ProductDetail(
  sku: sku,
  name: 'Joust Duffle Bag',
  urlKey: urlKey,
  typeId: 'simple',
  regularPrice: const Money(amount: 40, currency: 'AED'),
  finalPrice: const Money(amount: 40, currency: 'AED'),
);

/// A container with HubApp settled as [hubApp] (the splash settles it in the
/// app).
Future<ProviderContainer> _container({
  required HubAppState hubApp,
  FakeHubAppClient? public,
  CatalogRepository? catalog,
  ProductRouteRepository? routes,
}) async {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      if (public != null) publicGraphqlClientProvider.overrideWithValue(public),
      if (catalog != null) catalogRepositoryProvider.overrideWithValue(catalog),
      if (routes != null) productRouteRepositoryProvider.overrideWithValue(routes),
    ],
  );
  addTearDown(container.dispose);
  await container.read(hubAppProvider.future);
  return container;
}

const _available = HubAppState.available(kSampleHmAppConfig);

void main() {
  group('productMarketplaceFromJson — other sellers', () {
    test('reads the count and every offer, cheapest first as served', () {
      final marketplace = productMarketplaceFromJson(duffleJson());

      expect(marketplace.offerCount, 2);
      expect(marketplace.offers.map((o) => o.sku), ['SKU-2287', 'SKU-2150']);
      final enara = marketplace.offers.first;
      expect(enara.uid, 'uid-2287');
      expect(enara.urlKey, 'offer-2287');
      expect(enara.seller.name, 'ENARA');
      expect(enara.seller.rating, 4.4);
      expect(enara.price, const Money(amount: 34, currency: 'AED'));
      expect(enara.isDiscounted, isFalse);
      expect(enara.inStock, isTrue);
      expect(enara.addsDirectly, isTrue);
      expect(enara.dispatchTime!.label, '2-3 days');
      expect(enara.routeUrl, 'offer-2287.html');
      final hassan = marketplace.offers.last;
      expect(hassan.isDiscounted, isTrue);
      expect(hassan.regularPrice, const Money(amount: 45, currency: 'AED'));
      expect(hassan.dispatchTime, isNull);
    });

    test('a broken offer is left out, and the count never promises an '
        'empty sheet', () {
      final broken = productMarketplaceFromJson(
        duffleJson(
          count: 3,
          offers: [
            offerJson(1, 'a', 'A', price: 10),
            {...offerJson(2, 'b', 'B', price: 11), 'price': null},
            {...offerJson(3, 'c', 'C', price: 12), 'seller': null},
            'nonsense',
          ],
        ),
      );
      expect(broken.offers.map((o) => o.sku), ['SKU-1']);
      expect(broken.offerCount, 3, reason: 'the server counts every seller');

      expect(productMarketplaceFromJson(duffleJson(offers: [])).offerCount, 0);
      final lowCount = productMarketplaceFromJson(duffleJson(count: 1));
      expect(lowCount.offerCount, 2, reason: 'never fewer than the offers read');
      final noCount = productMarketplaceFromJson(duffleJson(count: null));
      expect(noCount.offerCount, 2);
    });

    test('a configurable offer is bought on its own page', () {
      final offer = productMarketplaceFromJson(
        duffleJson(offers: [offerJson(9, 'x', 'X', price: 5, type: 'configurable')]),
      ).offers.single;
      expect(offer.addsDirectly, isFalse);
    });

    test('a server without offers (P2) leaves the product page as it was', () {
      final plain = productMarketplaceFromJson({
        '__typename': 'SimpleProduct',
        'sku': 'DRESS',
        'hm_seller': sellerJson('loly', 'loly store'),
      });
      expect(plain.offerCount, 0);
      expect(plain.offers, isEmpty);
    });
  });

  group('ProductMarketplaceRepository', () {
    test('asks for offers with the seller, by url_key', () async {
      final server = fakeHubAppClient(_products(duffleJson()));

      final result = await ProductMarketplaceRepository(server).fetch('joust-duffle-bag');

      expect(server.requests.map(operationNameOf), ['HmProductMarketplace']);
      expect(server.requests.single.variables, {'urlKey': 'joust-duffle-bag'});
      expect(result!.offers, hasLength(2));
      expect(result.seller!.code, 'test_1');
    });

    test('an offer, which product search leaves out, is found by its URL', () async {
      final copy = {
        ...duffleJson(
          offers: [offerJson(1, 'test_1', 'Test 1', price: 28.9, regular: 34)],
          count: 1,
        ),
        'sku': 'SKU-2150',
        'hm_seller': sellerJson('hassan1', 'Hassan Store'),
      };
      final server = fakeHubAppClient({
        ..._products(null),
        'HmProductMarketplaceByRoute': {'route': copy},
      });

      final result = await ProductMarketplaceRepository(server).fetch('offer-2150');

      expect(server.requests.map(operationNameOf), [
        'HmProductMarketplace',
        'HmProductMarketplaceByRoute',
      ]);
      expect(server.requests.last.variables, {'url': 'offer-2150.html'});
      expect(result!.seller!.name, 'Hassan Store');
      expect(result.offers.single.seller.code, 'test_1');
    });

    test('a URL that is not a product is no product', () async {
      final server = fakeHubAppClient({
        ..._products(null),
        'HmProductMarketplaceByRoute': {
          'route': {'__typename': 'CmsPage'},
        },
      });
      expect(await ProductMarketplaceRepository(server).fetch('about-us'), isNull);
    });

    test('without offers: the seller alone, and no second look', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplaceSellers': {
          'products': {'items': <Object>[]},
        },
      });

      final result = await ProductMarketplaceRepository(
        server,
      ).fetch('dress', withOffers: false);

      expect(result, isNull);
      expect(server.requests.map(operationNameOf), ['HmProductMarketplaceSellers']);
    });

    test('isOffersMissing tells offers from sellers', () {
      expect(
        isOffersMissing(
          const HubAppMissing('Cannot query field "hm_offer_count" on type "ProductInterface".'),
        ),
        isTrue,
      );
      expect(
        isOffersMissing(
          const HubAppMissing('Cannot query field "hm_other_offers" on type "SimpleProduct".'),
        ),
        isTrue,
      );
      expect(
        isOffersMissing(
          const HubAppMissing('Cannot query field "hm_seller" on type "ProductInterface".'),
        ),
        isFalse,
      );
    });

    test('every GET stays well inside the URL limit', () {
      for (final document in [
        ProductMarketplaceQueries.document,
        ProductMarketplaceQueries.sellersDocument,
        ProductMarketplaceQueries.routeDocument,
      ]) {
        final encoded = Uri.encodeQueryComponent(compactGraphQLDocument(document));
        expect(encoded.length, lessThan(5000), reason: encoded);
      }
    });
  });

  group('productMarketplaceProvider', () {
    test('a server with sellers but no offers is asked again without them, '
        'and only without them from then on', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': hubAppMissingResponse(
          'hm_offer_count',
          type: 'ProductInterface',
        ),
        'HmProductMarketplaceSellers': {
          'products': {
            'items': [
              {
                '__typename': 'SimpleProduct',
                'sku': 'DRESS',
                'hm_seller': sellerJson('loly', 'loly store'),
              },
            ],
          },
        },
      });
      final c = await _container(hubApp: _available, public: server);

      final first = await c.read(productMarketplaceProvider('dress').future);
      expect(first!.seller!.code, 'loly');
      expect(first.offerCount, 0);
      expect(c.read(productOffersMissingProvider), isTrue);
      expect(c.read(marketplaceFeaturesProvider).sellers, isTrue);

      await c.read(productMarketplaceProvider('dress-2').future);
      expect(server.requests.map(operationNameOf), [
        'HmProductMarketplace',
        'HmProductMarketplaceSellers',
        'HmProductMarketplaceSellers',
      ]);
    });

    test('a server without sellers is remembered as before', () async {
      final server = fakeHubAppClient({
        'HmProductMarketplace': hubAppMissingResponse(
          'hm_seller',
          type: 'ProductInterface',
        ),
      });
      final c = await _container(hubApp: _available, public: server);

      expect(await c.read(productMarketplaceProvider('dress').future), isNull);
      expect(c.read(marketplaceFeaturesProvider).sellers, isFalse);
      expect(c.read(productOffersMissingProvider), isFalse);
    });

    test('Build 1 asks nothing', () async {
      final server = fakeHubAppClient(_products(duffleJson()));
      final c = await _container(hubApp: const HubAppState.unavailable(), public: server);

      expect(await c.read(productMarketplaceProvider('joust').future), isNull);
      expect(server.requests, isEmpty);
    });
  });

  group('the product page of an offer', () {
    test('the route query is the page\'s own query asked by URL', () {
      final derived = productDetailByRoute;
      expect(derived, contains(r'query ProductDetailByRoute($url: String!)'));
      expect(derived, contains(r'route(url: $url)'));
      expect(derived, contains('... on ProductInterface {'));
      expect(derived, isNot(contains('url_key: { eq:')));

      OperationDefinitionNode operation(String source) => gql_lang
          .parseString(source)
          .definitions
          .whereType<OperationDefinitionNode>()
          .single;
      final byKey = operation(CatalogQueries.productDetail);
      final byUrl = operation(derived);
      final items = (byKey.selectionSet.selections.single as FieldNode)
          .selectionSet!
          .selections
          .single as FieldNode;
      final inline = (byUrl.selectionSet.selections.single as FieldNode)
          .selectionSet!
          .selections
          .single as InlineFragmentNode;
      expect(
        gql_lang.printNode(inline.selectionSet),
        gql_lang.printNode(items.selectionSet!),
        reason: 'the same fields, so the page reads it the same way',
      );
    });

    test('a changed product query is caught rather than asked wrongly', () {
      expect(
        () => productDetailByRouteOf('query Other { products { items { sku } } }'),
        throwsStateError,
      );
    });

    test('with the Hub Market App, a url_key search does not know is read '
        'by its URL', () async {
      final catalog = _Catalog({});
      final routes = _Routes({'offer-2150.html': _page('5478', 'offer-2150')});
      final c = await _container(hubApp: _available, catalog: catalog, routes: routes);

      final page = await c.read(productDetailProvider('offer-2150').future);

      expect(page!.sku, '5478');
      expect(catalog.asked, ['offer-2150']);
      expect(routes.asked, ['offer-2150.html']);
    });

    test('a product search finds is never looked up twice', () async {
      final catalog = _Catalog({'joust': _page('24-MB01', 'joust')});
      final routes = _Routes(const {});
      final c = await _container(hubApp: _available, catalog: catalog, routes: routes);

      expect((await c.read(productDetailProvider('joust').future))!.sku, '24-MB01');
      expect(routes.asked, isEmpty);
    });

    test('Build 1 keeps "not found" without a second look', () async {
      final routes = _Routes({'offer-2150.html': _page('5478', 'offer-2150')});
      final c = await _container(
        hubApp: const HubAppState.unavailable(),
        catalog: _Catalog({}),
        routes: routes,
      );

      expect(await c.read(productDetailProvider('offer-2150').future), isNull);
      expect(routes.asked, isEmpty);
    });

    test('a failed second look is still "not found"', () async {
      final c = await _container(
        hubApp: _available,
        catalog: _Catalog({}),
        routes: _Routes(const {}, fail: true),
      );
      expect(await c.read(productDetailProvider('gone').future), isNull);
    });

    test('ProductRouteRepository reads route like products.items[0]', () async {
      final client = RecordingGraphQLClient(
        (request, document) => {
          'route': {
            '__typename': 'SimpleProduct',
            'sku': '5478',
            'name': 'Joust Duffle Bag',
            'url_key': 'joust-duffle-bag-1702962941',
            'stock_status': 'IN_STOCK',
            'price_range': {
              'minimum_price': {
                'regular_price': {'value': 40, 'currency': 'AED'},
                'final_price': {'value': 40, 'currency': 'AED'},
              },
            },
          },
        },
      );

      final page = await ProductRouteRepository(
        client.client,
      ).fetchDetail('joust-duffle-bag-1702962941.html');

      expect(page!.sku, '5478');
      expect(page.finalPrice, const Money(amount: 40, currency: 'AED'));
      expect(client.requests.single.variables, {
        'url': 'joust-duffle-bag-1702962941.html',
      });
      expect(client.documents.single, contains('route(url: \$url)'));
    });

    test('productRouteUrl adds the suffix once', () {
      expect(productRouteUrl('offer-2150'), 'offer-2150.html');
      expect(productRouteUrl(' offer-2150.html '), 'offer-2150.html');
    });
  });
}
