import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/wishlist/domain/wishlist_entry.dart';
import 'package:hubmarket_app/features/wishlist/presentation/wishlist_controller.dart';

import '../../support/fakes.dart';

ProviderContainer _container(FakeWishlistRepository repo, {String? token}) {
  final container = ProviderContainer(
    overrides: [
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      wishlistRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  container.listen(wishlistControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  return container;
}

void main() {
  group('WishlistController', () {
    test('toggle returns false (prompt sign-in) when signed out', () async {
      final container = _container(FakeWishlistRepository());
      final ok = await container
          .read(wishlistControllerProvider.notifier)
          .toggle('S1');
      expect(ok, isFalse);
    });

    test('loads on login and toggles add then remove', () async {
      final container = _container(FakeWishlistRepository());
      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();

      expect(container.read(wishlistControllerProvider).id, 'wl-1');

      final notifier = container.read(wishlistControllerProvider.notifier);
      final added = await notifier.toggle('CHANEL-COCO');
      expect(added, isTrue);
      expect(
        container.read(wishlistControllerProvider).contains('CHANEL-COCO'),
        isTrue,
      );

      await notifier.toggle('CHANEL-COCO');
      expect(
        container.read(wishlistControllerProvider).contains('CHANEL-COCO'),
        isFalse,
      );
    });

    test('clears the wishlist on logout', () async {
      final container = _container(FakeWishlistRepository());
      final notifier = container.read(wishlistControllerProvider.notifier);
      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();
      await notifier.toggle('CHANEL-COCO');
      expect(container.read(wishlistControllerProvider).entries, isNotEmpty);

      await container.read(authControllerProvider.notifier).logout();
      await pumpEventQueue();
      expect(container.read(wishlistControllerProvider).entries, isEmpty);
    });
  });

  group('WishlistState.count (the badge on the Wishlist tab)', () {
    WishlistEntry saved(int n) => WishlistEntry(
      id: 'item-$n',
      product: Product(sku: 'sku$n', name: 'Product $n', urlKey: 'p$n'),
    );

    Future<ProviderContainer> signedIn(FakeWishlistRepository repo) async {
      final container = _container(repo);
      await container
          .read(authControllerProvider.notifier)
          .login('layla@example.com', 'password1');
      await pumpEventQueue();
      return container;
    }

    test('is zero for a guest, and for a wishlist with nothing in it', () async {
      final guest = _container(FakeWishlistRepository(entries: [saved(1)]));
      expect(guest.read(wishlistControllerProvider).count, 0);

      final empty = await signedIn(FakeWishlistRepository());
      expect(empty.read(wishlistControllerProvider).count, 0);
    });

    test('counts what is saved once the wishlist has loaded', () async {
      final container = await signedIn(
        FakeWishlistRepository(entries: [saved(1), saved(2), saved(3)]),
      );
      expect(container.read(wishlistControllerProvider).count, 3);
    });

    test('goes up with every add and down with every remove', () async {
      final container = await signedIn(
        FakeWishlistRepository(entries: [saved(1), saved(2)]),
      );
      final notifier = container.read(wishlistControllerProvider.notifier);

      await notifier.toggle('NEW');
      expect(container.read(wishlistControllerProvider).count, 3);
      await notifier.toggle('sku1');
      expect(container.read(wishlistControllerProvider).count, 2);
      await notifier.removeSkus(['sku2', 'NEW']);
      expect(container.read(wishlistControllerProvider).count, 0);
    });

    test('is the count the store gives when the first page holds fewer than it '
        'saved, and still follows an add', () async {
      final container = await signedIn(
        FakeWishlistRepository(entries: [saved(1), saved(2)], itemsCount: 25),
      );
      expect(container.read(wishlistControllerProvider).entries, hasLength(2));
      expect(container.read(wishlistControllerProvider).count, 25);

      await container.read(wishlistControllerProvider.notifier).toggle('NEW');
      expect(container.read(wishlistControllerProvider).count, 26);
    });

    test('an answer without a count falls back on the entries in hand', () {
      final state = WishlistState(entries: [saved(1), saved(2)]);
      expect(state.itemsCount, isNull);
      expect(state.count, 2);
      // A count smaller than the entries never lowers it.
      expect(WishlistState(entries: [saved(1), saved(2)], itemsCount: 1).count, 2);
    });

    test('goes back to zero at sign-out', () async {
      final container = await signedIn(
        FakeWishlistRepository(entries: [saved(1)]),
      );
      expect(container.read(wishlistControllerProvider).count, 1);

      await container.read(authControllerProvider.notifier).logout();
      await pumpEventQueue();
      expect(container.read(wishlistControllerProvider).count, 0);
    });
  });
}
