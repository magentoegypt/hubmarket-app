import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/data/best_sellers_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/deals/data/deals_repository.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';
import 'package:hubmarket_app/features/stores/data/store_products_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';

import '../../support/marketplace_fakes.dart';

/// A card product as a listing serves it, with its seller when [seller].
Map<String, dynamic> _card(String sku, {Map<String, dynamic>? seller}) => {
  '__typename': 'SimpleProduct',
  'sku': sku,
  'name': 'Product $sku',
  'url_key': sku,
  'stock_status': 'IN_STOCK',
  'new_from_date': null,
  'new_to_date': null,
  'rating_summary': 0,
  'review_count': 0,
  'image': null,
  'price_range': {
    'minimum_price': {
      'regular_price': {'value': 10, 'currency': 'AED'},
      'final_price': {'value': 10, 'currency': 'AED'},
    },
  },
  'hm_seller': ?seller,
};

/// The listing answers of a server with or without HubAppVendors: a document
/// asking for `hm_seller` gets the sellers, or "Cannot query field" when
/// [vendors] is false.
Object Function(Request, String) _server({bool vendors = true}) =>
    (request, document) {
      final twin = document.contains('hm_seller');
      if (twin && !vendors) return missingFieldResponse('hm_seller', 'SimpleProduct');
      final items = [
        _card('A', seller: twin ? sellerJson('MIA', 'MIA CO') : null),
        _card(
          'B',
          seller: twin
              ? sellerJson(null, 'Hub Market', marketplace: true)
              : null,
        ),
      ];
      final page = {
        'total_count': items.length,
        'page_info': {'current_page': 1, 'page_size': 20, 'total_pages': 1},
        'items': items,
      };
      return switch (rootFieldOf(request)) {
        'products' => {
          'products': {...page, 'aggregations': <Object>[]},
        },
        'hmDeals' => {
          'hmDeals': {...page, 'countdown_ends_at': null},
        },
        'hmBestSellers' => {'hmBestSellers': page},
        'hmAppHome' => {
          'hmAppHome': {
            'store_code': 'en',
            'generated_at': '2026-09-30T08:00:00Z',
            'sections': [
              {
                'id': 1,
                'type': 'BEST_SELLERS',
                'title': 'Best sellers',
                'limit': 8,
                'personalizable': false,
                'products': items,
              },
            ],
          },
        },
        'customer' => {
          'customer': {
            'wishlists': [
              {
                // Read through a fragment: the cache checks its type.
                '__typename': 'Wishlist',
                'id': '1',
                'items_v2': {
                  'items': [
                    for (final item in items) {'id': item['sku'], 'product': item},
                  ],
                },
              },
            ],
          },
        },
        final other => throw StateError('unexpected $other'),
      };
    };

const _on = MarketplaceFeatures(sellers: true, listingSellers: true);

void main() {
  group('a server listing HubAppVendors', () {
    test('the PLP asks who sells each card and names the seller', () async {
      final server = RecordingGraphQLClient(_server());
      final gate = RecordingMarketplaceGate(_on);

      final page = await CatalogRepository(
        server.client,
        marketplace: gate,
      ).fetchProducts(categoryUid: 'Mg==');

      expect(server.documents.single, contains('...HmCardSeller'));
      expect(server.documents.single, contains('hm_seller'));
      expect(page.items.first.sellerName, 'MIA CO');
      expect(page.items.first.sellerKnown, isTrue);
      // Hub Market's own product: known, nothing to name.
      expect(page.items.last.sellerKnown, isTrue);
      expect(page.items.last.sellerName, isNull);
    });

    test('deals, best sellers, the Home rails and the wishlist ask too', () async {
      final server = RecordingGraphQLClient(_server());
      final gate = RecordingMarketplaceGate(_on);

      final deals = await DealsRepository(server.client, marketplace: gate)
          .fetchDeals();
      final best = await BestSellersRepository(server.client, marketplace: gate)
          .fetchPage();
      final home = await HmHomeRepository(server.client, marketplace: gate)
          .fetchHome(HmAudience.guest);
      final wishlist = await WishlistRepository(server.client, marketplace: gate)
          .fetchWishlist();

      expect(server.documents, everyElement(contains('...HmCardSeller')));
      expect(deals.items.first.sellerName, 'MIA CO');
      expect(best.items.first.sellerName, 'MIA CO');
      expect(home.sections.single.products.first.sellerName, 'MIA CO');
      expect(wishlist!.entries.first.product.sellerName, 'MIA CO');
    });

    test("a store page's category read draws no card and asks no seller", () async {
      final server = RecordingGraphQLClient(_server());
      final repository = StoreProductsRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(_on),
      );

      await repository.fetchProducts(vendorEntityId: 12, pageSize: 1);
      await repository.fetchProducts(vendorEntityId: 12);

      expect(server.documents.first, isNot(contains('hm_seller')));
      expect(server.documents.last, contains('...HmCardSeller'));
    });
  });

  group('a server without the seller line', () {
    test('Build 1 (or a HubApp that does not list vendors) sends the listing as written', () async {
      final server = RecordingGraphQLClient(_server(vendors: false));

      final page = await CatalogRepository(server.client).fetchProducts(
        search: 'sofa',
      );
      await DealsRepository(server.client).fetchDeals();

      expect(server.documents, everyElement(isNot(contains('hm_seller'))));
      expect(page.items.first.sellerKnown, isFalse);
    });

    test('hm_seller turned down: the listing goes again as written, and the gate stops asking', () async {
      final server = RecordingGraphQLClient(_server(vendors: false));
      final gate = RecordingMarketplaceGate(_on);

      final home = await HmHomeRepository(server.client, marketplace: gate)
          .fetchHome(HmAudience.guest);
      final page = await CatalogRepository(server.client, marketplace: gate)
          .fetchProducts(categoryUid: 'Mg==');

      // The Home is not lost to the one field: it is asked again, plain.
      expect(home.sections.single.products, hasLength(2));
      expect(gate.sellersMissingCalls, 1);
      expect(server.documents, hasLength(3));
      expect(server.documents[0], contains('hm_seller'));
      expect(server.documents[1], isNot(contains('hm_seller')));
      expect(server.documents[2], isNot(contains('hm_seller')));
      expect(page.items.first.sellerKnown, isFalse);
    });

    test("the list's own field missing is still HubApp missing", () async {
      final server = RecordingGraphQLClient(
        (request, document) => missingFieldResponse('hmDeals', 'Query'),
      );
      final gate = RecordingMarketplaceGate(_on);

      await expectLater(
        DealsRepository(server.client, marketplace: gate).fetchDeals(),
        throwsA(isA<HubAppMissing>()),
      );
      expect(gate.sellersMissingCalls, 0);
      expect(server.documents, hasLength(1));
    });
  });
}
