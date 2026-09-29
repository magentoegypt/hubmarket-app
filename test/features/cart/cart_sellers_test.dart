import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/bundle_cart_request.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/marketplace_fakes.dart';

/// `cart` data with two lines, each with its seller when [withSellers].
Map<String, dynamic> _cart({required bool withSellers}) => {
  '__typename': 'Cart',
  'id': 'cart-1',
  'total_quantity': 2,
  'items': [
    {
      '__typename': 'SimpleCartItem',
      'uid': 'line-sofa',
      'quantity': 1,
      'product': {'__typename': 'SimpleProduct', 'sku': 'SOFA', 'name': 'Sofa'},
      if (withSellers) 'hm_seller': sellerJson('mia', 'MIA CO'),
    },
    {
      '__typename': 'SimpleCartItem',
      'uid': 'line-dress',
      'quantity': 1,
      'product': {'__typename': 'SimpleProduct', 'sku': 'DRESS', 'name': 'Dress'},
      if (withSellers) 'hm_seller': sellerJson('loly', 'loly store'),
    },
  ],
};

void main() {
  group('CartRepository without HubApp', () {
    test('sends today\'s document, with no seller selection', () async {
      final server = RecordingGraphQLClient(
        (_, __) => {'cart': _cart(withSellers: false)},
      );
      final cart = await CartRepository(
        server.client,
        marketplace: const FixedMarketplaceGate(),
      ).getCart('cart-1');

      expect(server.documents.single, isNot(contains('hm_seller')));
      expect(cart.items.map((i) => i.seller), everyElement(isNull));
    });
  });

  group('CartRepository with HubApp', () {
    test('asks for each line\'s seller and reads it', () async {
      final server = RecordingGraphQLClient(
        (_, __) => {'cart': _cart(withSellers: true)},
      );
      final cart = await CartRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(),
      ).getCart('cart-1');

      expect(server.documents.single, contains('hm_seller'));
      expect(cart.items.map((i) => i.seller?.code), ['mia', 'loly']);
      expect(cart.items.first.seller!.name, 'MIA CO');
    });

    test('every cart mutation carries the seller selection too', () async {
      final server = RecordingGraphQLClient((request, _) {
        final field = rootFieldOf(request);
        return switch (field) {
          'mergeCarts' => {'mergeCarts': _cart(withSellers: true)},
          _ => {
            field: {'cart': _cart(withSellers: true)},
          },
        };
      });
      final repository = CartRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(),
      );

      await repository.addProducts('cart-1', [
        {'sku': 'SOFA', 'quantity': 1},
      ]);
      await repository.updateItem('cart-1', 'line-sofa', 2);
      await repository.removeItem('cart-1', 'line-sofa');
      await repository.applyCoupon('cart-1', 'SAVE10');
      await repository.removeCoupon('cart-1');
      final merged = await repository.mergeCarts('guest', 'cart-1');

      expect(server.documents, hasLength(6));
      expect(server.documents, everyElement(contains('hm_seller')));
      expect(merged.items.first.seller?.code, 'mia');
    });

    test('a server without hm_seller gets today\'s document, once told', () async {
      final server = RecordingGraphQLClient(
        (_, document) => document.contains('hm_seller')
            ? missingFieldResponse('hm_seller', 'CartItemInterface')
            : {'cart': _cart(withSellers: false)},
      );
      final gate = RecordingMarketplaceGate();
      final repository = CartRepository(server.client, marketplace: gate);

      final cart = await repository.getCart('cart-1');
      expect(cart.items, hasLength(2));
      expect(gate.sellersMissingCalls, 1);
      expect(server.documents, hasLength(2));
      expect(server.documents.last, isNot(contains('hm_seller')));

      // The gate now says no, so the next call goes straight to the live one.
      await repository.getCart('cart-1');
      expect(server.documents, hasLength(3));
      expect(server.documents.last, isNot(contains('hm_seller')));
    });

    test('a real failure is not mistaken for a missing module', () async {
      final server = RecordingGraphQLClient(
        (_, __) => Exception('Failed host lookup (test)'),
      );
      final gate = RecordingMarketplaceGate();

      await expectLater(
        CartRepository(server.client, marketplace: gate).getCart('cart-1'),
        throwsA(isA<Failure>()),
      );
      expect(gate.sellersMissingCalls, 0);
    });
  });

  group('CartRepository.addBundle', () {
    const request = BundleCartRequest(
      sku: 'HM-DEMO-BUNDLE-FITNESS',
      quantity: 2,
      selections: [
        BundleSelectionInput(selectionUid: 'YnVuZGxlLzIwLzYzLzE='),
        BundleSelectionInput(
          selectionUid: 'YnVuZGxlLzIxLzY0LzE=',
          quantity: 3,
          configurableOptionUids: ['Y29uZmlndXJhYmxlLzkzLzUz'],
        ),
      ],
    );

    test('sends hmAddBundleToCart with scalar variables only', () async {
      final server = RecordingGraphQLClient(
        (_, __) => {
          'hmAddBundleToCart': {
            'cart': _cart(withSellers: true),
            'user_errors': <dynamic>[],
          },
        },
      );
      final cart = await CartRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(),
      ).addBundle('cart-1', request);

      final sent = server.requests.single;
      expect(sent.variables, {
        'cartId': 'cart-1',
        'sku': 'HM-DEMO-BUNDLE-FITNESS',
        'quantity': 2.0,
        's0': 'YnVuZGxlLzIwLzYzLzE=',
        's1': 'YnVuZGxlLzIxLzY0LzE=',
        'q1': 3.0,
        'c1': ['Y29uZmlndXJhYmxlLzkzLzUz'],
      });
      final document = server.documents.single;
      expect(document, isNot(contains('HmAddBundleToCartInput')));
      expect(document, isNot(contains('HmBundleSelectionInput')));
      expect(document, contains('hm_seller'));
      expect(cart.items.first.seller?.code, 'mia');
    });

    test('a refused selection comes back with the store\'s message', () async {
      final server = RecordingGraphQLClient(
        (_, __) => {
          'hmAddBundleToCart': {
            'cart': _cart(withSellers: false),
            'user_errors': [
              {'code': 'INSUFFICIENT_STOCK', 'message': 'Yoga Brick is sold out'},
            ],
          },
        },
      );

      await expectLater(
        CartRepository(
          server.client,
          marketplace: RecordingMarketplaceGate(),
        ).addBundle('cart-1', request),
        throwsA(
          isA<Failure>().having(
            (f) => f.detail,
            'detail',
            'Yoga Brick is sold out',
          ),
        ),
      );
    });

    test('a server without HubAppBundle turns bundles off', () async {
      final server = RecordingGraphQLClient(
        (_, __) => missingFieldResponse('hmAddBundleToCart', 'Mutation'),
      );
      final gate = RecordingMarketplaceGate();

      await expectLater(
        CartRepository(server.client, marketplace: gate).addBundle(
          'cart-1',
          request,
        ),
        throwsA(isA<HubAppMissing>()),
      );
      expect(gate.bundlesMissingCalls, 1);
      expect(gate.features.bundles, isFalse);
    });

    test('without hm_seller the bundle still goes, without sellers', () async {
      final server = RecordingGraphQLClient(
        (_, document) => document.contains('hm_seller')
            ? missingFieldResponse('hm_seller', 'CartItemInterface')
            : {
                'hmAddBundleToCart': {
                  'cart': _cart(withSellers: false),
                  'user_errors': <dynamic>[],
                },
              },
      );
      final gate = RecordingMarketplaceGate();

      final cart = await CartRepository(
        server.client,
        marketplace: gate,
      ).addBundle('cart-1', request);

      expect(cart.items, hasLength(2));
      expect(gate.sellersMissingCalls, 1);
      expect(gate.bundlesMissingCalls, 0);
    });
  });
}
