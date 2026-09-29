import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/data/best_sellers_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart'
    show ProductSortField;
import 'package:hubmarket_app/features/stores/data/store_products_repository.dart';
import 'package:hubmarket_app/features/stores/data/stores_repository.dart';
import 'package:hubmarket_app/features/stores/domain/store.dart';

import '../../../support/hubapp_fakes.dart';
import '../../../support/store_fixtures.dart';

void main() {
  group('StoresRepository.fetchStores (hmStores)', () {
    test('reads the cards, the count and the paging', () async {
      final backend = FakeStoresBackend(
        (_) => storesData(sampleStoreCards(), total: 12, pages: 3),
      );
      final page = await StoresRepository(backend.client).fetchStores();

      expect(page.items.map((c) => c.code), [
        'MIA',
        'loly',
        'ENARA',
        'future_building',
        'walmart',
      ]);
      expect(page.totalCount, 12);
      expect(page.pageInfo.currentPage, 1);
      expect(page.hasMore, isTrue);

      final mia = page.items.first;
      expect(mia.vendorEntityId, 12);
      expect(mia.name, 'MIA CO');
      expect(mia.rating, 4.8);
      expect(mia.reviewCount, 126);
      expect(mia.productCount, 38);
      expect(mia.isFeatured, isTrue);
      expect(mia.dispatchTime?.label, 'Next day');
      expect(mia.joinedAt, DateTime.utc(2023, 6, 12, 8));
      expect(mia.webUrl, 'https://hub-market.magento2.click/en/shop/MIA');
      expect(mia.isRated, isTrue);
      expect(page.items.last.isRated, isFalse);
    });

    test(
      'declares no Hm* variable: the sort and filter shape are inline',
      () async {
        final backend = FakeStoresBackend((_) => storesData(const []));
        await StoresRepository(backend.client).fetchStores(
          query: const StoreListQuery(
            categoryId: 74,
            name: '  mia ',
            sort: StoreSort.topRated,
          ),
          pageSize: 20,
          currentPage: 2,
        );

        final request = backend.of('HmStores').single;
        expect(request.document, contains('sort: TOP_RATED'));
        expect(
          request.document,
          contains(
            'filter: {featured: \$featured, category_id: \$categoryId, name: \$name}',
          ),
        );
        expect(request.variableTypes, isNot(contains(startsWith('Hm'))));
        expect(request.variables, {
          'pageSize': 20,
          'currentPage': 2,
          'featured': null,
          'categoryId': 74,
          'name': 'mia',
        });
      },
    );

    test('every sort goes inline, featured by default', () async {
      final backend = FakeStoresBackend((_) => storesData(const []));
      final repository = StoresRepository(backend.client);
      for (final sort in StoreSort.values) {
        await repository.fetchStores(query: StoreListQuery(sort: sort));
      }
      expect(
        [
          for (final r in backend.requests)
            RegExp(r'sort: (\w+)').firstMatch(r.document)!.group(1),
        ],
        ['FEATURED', 'TOP_RATED', 'NEWEST', 'NAME', 'PRODUCT_COUNT'],
      );
    });

    test('a page size above 50 is capped: the backend refuses more', () async {
      final backend = FakeStoresBackend((_) => storesData(const []));
      await StoresRepository(backend.client).fetchStores(pageSize: 200);
      expect(backend.requests.single.variables['pageSize'], 50);
    });

    test('cards without a code or link are left out', () async {
      final backend = FakeStoresBackend(
        (_) => storesData([
          miaCard(),
          {...miaCard(), 'code': ' '},
          {...miaCard(), 'code': 'nolink', 'link': null},
        ]),
      );
      final page = await StoresRepository(backend.client).fetchStores();
      expect(page.items.map((c) => c.code), ['MIA']);
    });

    test('a server without the seller API throws HubAppMissing', () async {
      final backend = FakeStoresBackend(
        (_) => hubAppMissingResponse('hmStores'),
      );
      await expectLater(
        StoresRepository(backend.client).fetchStores(),
        throwsA(isA<HubAppMissing>()),
      );
    });
  });

  group('StoresRepository.fetchStore (hmStore)', () {
    test('reads the card, texts and policies', () async {
      final backend = FakeStoresBackend((_) => miaStoreData());
      final profile = await StoresRepository(
        backend.client,
      ).fetchStore(' MIA ');

      expect(backend.requests.single.variables, {'code': 'MIA'});
      expect(backend.requests.single.variableTypes, ['String']);
      expect(profile!.card.name, 'MIA CO');
      expect(
        profile.shortDescription,
        'Modern furniture for homes and offices',
      );
      expect(profile.aboutHtml, startsWith('<p>MIA CO designs'));
      expect(profile.hasPolicies, isTrue);
      expect(profile.bannerUrl, isNull);
    });

    test('null for a code that is no approved seller', () async {
      final backend = FakeStoresBackend((_) => {'hmStore': null});
      expect(await StoresRepository(backend.client).fetchStore('gone'), isNull);
    });

    test('an empty code asks nothing', () async {
      final backend = FakeStoresBackend((_) => miaStoreData());
      expect(await StoresRepository(backend.client).fetchStore('  '), isNull);
      expect(backend.requests, isEmpty);
    });
  });

  group('StoreProductsRepository (products by vendor_id)', () {
    test(
      'filters on the seller with a FULL match, never eq or PARTIAL',
      () async {
        final backend = FakeStoresBackend((_) => productsData(miaProducts()));
        final page = await StoreProductsRepository(
          backend.client,
        ).fetchProducts(vendorEntityId: 12);

        final request = backend.of('Products').single;
        expect(request.variables['filter'], {
          'vendor_id': {'match': '12', 'match_type': 'FULL'},
        });
        expect(request.variables.containsKey('search'), isFalse);
        expect(request.variables.containsKey('sort'), isFalse);
        expect(page.items.map((p) => p.name), contains('Corner Sofa Bed'));
        expect(page.items.first.typeId, 'simple');
        // The seller filter is not offered as a facet on its own page.
        expect(page.aggregations.map((a) => a.attributeCode), ['category_uid']);
      },
    );

    test(
      'the store search, attribute filters, price and sort ride along',
      () async {
        final backend = FakeStoresBackend((_) => productsData(const []));
        await StoreProductsRepository(backend.client).fetchProducts(
          vendorEntityId: 12,
          search: ' sofa ',
          attributeFilters: {
            'category_uid': {'NzU='},
            'color': <String>{},
          },
          priceFrom: 10,
          priceTo: 500,
          sort: ProductSortField.priceDesc,
          pageSize: 20,
          currentPage: 3,
        );

        final variables = backend.requests.single.variables;
        expect(variables['search'], 'sofa');
        expect(variables['filter'], {
          'vendor_id': {'match': '12', 'match_type': 'FULL'},
          'category_uid': {
            'in': ['NzU='],
          },
          'price': {'from': '10.00', 'to': '500.00'},
        });
        expect(variables['sort'], {'price': 'DESC'});
        expect(variables['currentPage'], 3);
      },
    );
  });

  group('BestSellersRepository (hmBestSellers)', () {
    test('reads the products, capped at 50 a page', () async {
      final backend = FakeStoresBackend((_) => bestSellersData());
      final products = await BestSellersRepository(
        backend.client,
      ).fetch(pageSize: 80);

      expect(backend.requests.single.operation, 'HmBestSellers');
      expect(backend.requests.single.variables['pageSize'], 50);
      expect(products.map((p) => p.name), [
        'Joust Duffle Bag',
        'Strive Shoulder Pack',
        'Crown Summit Backpack',
      ]);
      expect(products.first.discountPercent, 15);
    });

    test('a server without it throws HubAppMissing', () async {
      final backend = FakeStoresBackend(
        (_) => hubAppMissingResponse('hmBestSellers'),
      );
      await expectLater(
        BestSellersRepository(backend.client).fetch(),
        throwsA(isA<HubAppMissing>()),
      );
    });
  });
}
