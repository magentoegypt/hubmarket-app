import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_queries.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';

import '../../support/fakes.dart';
import '../../support/marketplace_fakes.dart';

/// The cart as `hmAddCreditToCart` answers it: the new credit line.
Map<String, dynamic> _cart({required bool withSellers}) => {
  '__typename': 'Cart',
  'id': 'cart-1',
  'total_quantity': 1,
  'items': [
    {
      '__typename': 'VirtualCartItem',
      'uid': 'line-credit',
      'quantity': 1,
      'product': {
        '__typename': 'VirtualProduct',
        'sku': 'hm-credit-any',
        'name': 'Store credit',
      },
      'prices': {
        '__typename': 'CartItemPrices',
        'price': {'__typename': 'Money', 'value': 150, 'currency': 'AED'},
        'row_total': {'__typename': 'Money', 'value': 150, 'currency': 'AED'},
      },
      if (withSellers) 'hm_seller': sellerJson(null, 'Hub Market'),
    },
  ],
};

Map<String, dynamic> _added({
  required bool withSellers,
  List<Map<String, String>> errors = const [],
}) => {
  'hmAddCreditToCart': {
    '__typename': 'AddProductsToCartOutput',
    'cart': _cart(withSellers: withSellers),
    'user_errors': [
      for (final error in errors)
        {'__typename': 'CartUserInputError', ...error},
    ],
  },
};

ProviderContainer _container(FakeCartRepository repo) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  container.listen(cartControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  return container;
}

void main() {
  group('CartRepository.addCredit', () {
    test('sends hmAddCreditToCart with scalar variables only', () async {
      final server = RecordingGraphQLClient(
        (_, __) => _added(withSellers: true),
      );
      final cart = await CartRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(),
      ).addCredit('cart-1', 150);

      final sent = server.requests.single;
      expect(rootFieldOf(sent), 'hmAddCreditToCart');
      expect(sent.variables, {'cartId': 'cart-1', 'amount': 150.0});
      final document = server.documents.single;
      expect(document, isNot(contains('HmAddCreditToCartInput')));
      expect(document, contains('hm_seller'));
      expect(cart.items.single.sku, 'hm-credit-any');
      expect(cart.items.single.rowTotal?.amount, 150);
    });

    test('no document declares a variable of an Hm* type', () {
      expect(
        CartQueries.addCredit,
        isNot(matches(RegExp(r'\$\w+\s*:\s*\[?Hm'))),
      );
    });

    test('the store\'s refusal comes back with its message', () async {
      final server = RecordingGraphQLClient(
        (_, __) => _added(
          withSellers: false,
          errors: [
            {
              'code': 'INVALID_PARAMETER_VALUE',
              'message': 'Enter a whole amount from AED 10 to AED 1,000.',
            },
          ],
        ),
      );

      await expectLater(
        CartRepository(
          server.client,
          marketplace: RecordingMarketplaceGate(),
        ).addCredit('cart-1', 5),
        throwsA(
          isA<Failure>()
              .having((f) => f.kind, 'kind', FailureKind.server)
              .having(
                (f) => f.detail,
                'detail',
                'Enter a whole amount from AED 10 to AED 1,000.',
              ),
        ),
      );
    });

    test('a server without the mutation throws HubAppMissing', () async {
      final server = RecordingGraphQLClient(
        (_, __) => missingFieldResponse('hmAddCreditToCart', 'Mutation'),
      );
      final gate = RecordingMarketplaceGate();

      await expectLater(
        CartRepository(server.client, marketplace: gate).addCredit('c', 50),
        throwsA(isA<HubAppMissing>()),
      );
      // Bundles and sellers have nothing to do with it.
      expect(gate.bundlesMissingCalls, 0);
      expect(gate.sellersMissingCalls, 0);
    });

    test('without hm_seller the credit still goes, without sellers', () async {
      final server = RecordingGraphQLClient(
        (_, document) => document.contains('hm_seller')
            ? missingFieldResponse('hm_seller', 'CartItemInterface')
            : _added(withSellers: false),
      );
      final gate = RecordingMarketplaceGate();

      final cart = await CartRepository(
        server.client,
        marketplace: gate,
      ).addCredit('cart-1', 150);

      expect(cart.items, hasLength(1));
      expect(server.requests, hasLength(2));
      expect(gate.sellersMissingCalls, 1);
    });
  });

  group('CartController.addCreditToCart', () {
    test('adds the credit to the signed-in customer\'s cart', () async {
      final repo = FakeCartRepository();
      final container = _container(repo);
      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();

      await container
          .read(cartControllerProvider.notifier)
          .addCreditToCart(250);

      expect(repo.creditAmounts, [250.0]);
      expect(repo.createCalls, 0);
      final state = container.read(cartControllerProvider);
      expect(state.cart.id, 'customer-1');
      expect(state.cart.items.single.sku, 'store-credit');
      expect(state.isMutating, isFalse);
    });

    test('a refusal leaves the cart as it was and rethrows', () async {
      final repo = FakeCartRepository()
        ..addCreditFailure = const Failure(
          FailureKind.server,
          detail: 'Store credit can\'t be bought at the moment.',
        );
      final container = _container(repo);
      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();

      await expectLater(
        container.read(cartControllerProvider.notifier).addCreditToCart(100),
        throwsA(isA<Failure>()),
      );
      final state = container.read(cartControllerProvider);
      expect(state.cart.items, isEmpty);
      expect(state.isMutating, isFalse);
      expect(repo.creditAmounts, [100.0]);
    });
  });
}
