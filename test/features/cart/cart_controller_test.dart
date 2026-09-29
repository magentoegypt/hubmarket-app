import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';

import '../../support/fakes.dart';

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
  // Keep the controllers alive (they listen to one another).
  container.listen(cartControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  return container;
}

void main() {
  group('CartController', () {
    test('addToCart creates a cart and adds the item', () async {
      final repo = FakeCartRepository();
      final container = _container(repo);
      await container
          .read(cartControllerProvider.notifier)
          .addToCart(sku: 'CHANEL-COCO');

      final state = container.read(cartControllerProvider);
      expect(repo.createCalls, 1);
      expect(state.itemCount, 1);
      expect(state.cart.items.single.sku, 'CHANEL-COCO');
    });

    test('setQuantity updates and removeItem empties the cart', () async {
      final container = _container(FakeCartRepository());
      final notifier = container.read(cartControllerProvider.notifier);
      await notifier.addToCart(sku: 'SKU1');
      final uid = container.read(cartControllerProvider).cart.items.single.uid;

      await notifier.setQuantity(uid, 4);
      expect(
        container.read(cartControllerProvider).cart.items.single.quantity,
        4,
      );

      await notifier.removeItem(uid);
      expect(container.read(cartControllerProvider).cart.isEmpty, isTrue);
    });

    test('applyCoupon records the coupon', () async {
      final container = _container(FakeCartRepository());
      final notifier = container.read(cartControllerProvider.notifier);
      await notifier.addToCart(sku: 'SKU1');
      await notifier.applyCoupon('SAVE10');
      expect(
        container.read(cartControllerProvider).cart.totals.appliedCoupon,
        'SAVE10',
      );
    });

    test('merges the guest cart into the customer cart on login', () async {
      final repo = FakeCartRepository();
      final container = _container(repo);
      await container
          .read(cartControllerProvider.notifier)
          .addToCart(sku: 'SKU1');

      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();

      expect(repo.mergeCalls, 1);
      expect(container.read(cartControllerProvider).cart.id, 'customer-1');
    });
  });
}
