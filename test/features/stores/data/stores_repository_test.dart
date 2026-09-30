import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/data/best_sellers_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart'
    show ProductSortField;
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';
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

  group('the P3.1 fields (the server lists vendors)', () {
    const on = FixedMarketplaceGate(MarketplaceFeatures(storeExtras: true));

    test('without them the documents are the P3 ones', () async {
      final backend = FakeStoresBackend(
        (r) => r.operation == 'HmStore'
            ? miaStoreData()
            : storesData(sampleStoreCards()),
      );
      final repository = StoresRepository(backend.client);
      final page = await repository.fetchStores();
      final profile = await repository.fetchStore('MIA');

      for (final request in backend.requests) {
        expect(request.document, isNot(contains('HmStoreCardExtras')));
        expect(request.document, isNot(contains('HmStorePageExtras')));
      }
      expect(page.items.first.primaryCategory, isNull);
      expect(page.items.first.facetValue, isNull);
      expect(profile!.phone, isNull);
      expect(profile.location, isNull);
      expect(profile.salesCount, isNull);
    });

    test('cards carry their category and facet value', () async {
      final backend = FakeStoresBackend((_) => storesData(sampleStoreCards()));
      final page = await StoresRepository(
        backend.client,
        marketplace: on,
      ).fetchStores(query: const StoreListQuery(sort: StoreSort.topRated));

      final request = backend.requests.single;
      expect(request.document, contains('...HmStoreCardExtras'));
      expect(request.document, contains('sort: TOP_RATED'));
      expect(request.variableTypes, isNot(contains(startsWith('Hm'))));
      final mia = page.items.first;
      expect(mia.primaryCategory!.name, 'Furniture');
      expect(mia.primaryCategory!.uid, 'MzQ=');
      expect(mia.primaryCategory!.count, 38);
      expect(mia.categoryName, 'Furniture');
      expect(mia.facetValue, 'MIA CO');
    });

    test(
      'the page carries what the website publishes: phone, location, sales',
      () async {
        final backend = FakeStoresBackend((_) => miaStoreData());
        final profile = await StoresRepository(
          backend.client,
          marketplace: on,
        ).fetchStore('MIA');

        expect(
          backend.requests.single.document,
          contains('...HmStorePageExtras'),
        );
        expect(profile!.phone, '+971 50 123 4567');
        // Dialled as the website's tel: link does: digits and + only.
        expect(profile.phoneUri, Uri.parse('tel:+971501234567'));
        expect(profile.location, 'Dubai, United Arab Emirates');
        expect(profile.salesCount, 1240);
        expect(profile.card.categoryName, 'Furniture');
      },
    );

    test(
      'a server that turns them down is asked again without them',
      () async {
        final backend = FakeStoresBackend(
          (r) => r.document.contains('HmStoreCardExtras')
              ? hubAppMissingResponse('primary_category', type: 'HmStoreCard')
              : storesData(sampleStoreCards()),
        );
        final page = await StoresRepository(
          backend.client,
          marketplace: on,
        ).fetchStores();

        expect(backend.requests, hasLength(2));
        expect(
          backend.requests.last.document,
          isNot(contains('HmStoreCardExtras')),
        );
        expect(page.items, hasLength(5));
        expect(page.items.first.primaryCategory, isNull);
      },
    );

    test(
      "the Reviews tab: the card's rating and this store view's reviews",
      () async {
        final backend = FakeStoresBackend((_) => miaReviewsData());
        final page = await StoresRepository(backend.client).fetchStoreReviews(
          ' MIA ',
          pageSize: 80,
          currentPage: 2,
        );

        final request = backend.requests.single;
        expect(request.operation, 'HmStoreReviews');
        expect(request.variables, {
          'code': 'MIA',
          'pageSize': 50,
          'currentPage': 2,
        });
        expect(request.variableTypes, ['String', 'Int', 'Int']);
        expect(page!.rating, 4.8);
        expect(page.reviewCount, 126);
        expect(page.totalCount, 2);
        final first = page.items.first;
        expect(first.nickname, 'Sara K.');
        expect(first.title, 'Great sofa');
        expect(first.stars, 5);
        expect(first.createdAt, DateTime.utc(2026, 9, 20, 8, 15));
        expect(first.product!.urlKey, 'sofabed123');
        // A product the storefront no longer lists is named, not linked.
        expect(page.items.last.title, isNull);
        expect(page.items.last.product!.urlKey, isNull);
      },
    );

    test(
      'reviews of a code that is no approved seller: null; empty asks nothing',
      () async {
        final backend = FakeStoresBackend((_) => {'hmStoreReviews': null});
        final repository = StoresRepository(backend.client);
        expect(await repository.fetchStoreReviews('gone'), isNull);
        expect(await repository.fetchStoreReviews(' '), isNull);
        expect(backend.requests, hasLength(1));
      },
    );

    test('the chips: sellers per category, none with zero', () async {
      final backend = FakeStoresBackend(
        (_) => {
          'hmStoreCategories': {
            'total_count': 22,
            'items': [
              {'id': 34, 'uid': 'MzQ=', 'name': 'Furniture', 'count': 3},
              {'id': 38, 'uid': 'Mzg=', 'name': 'Grocery', 'count': 0},
            ],
          },
        },
      );
      final chips = await StoresRepository(
        backend.client,
      ).fetchStoreCategories();

      expect(backend.requests.single.operation, 'HmStoreCategories');
      expect(chips.totalCount, 22);
      expect(chips.items.map((c) => (c.name, c.count)), [('Furniture', 3)]);
    });
  });
}
