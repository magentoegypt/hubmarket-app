import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
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
}
