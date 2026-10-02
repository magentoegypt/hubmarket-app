import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/product_navigation.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/presentation/checkout_controller.dart';
import 'package:hubmarket_app/features/personalization/data/insights_tracker.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/wishlist/presentation/wishlist_controller.dart';

import '../../support/fakes.dart';
import '../../support/insights_fakes.dart';

/// Where the app tells the tracker what the shopper does. The tracker itself is
/// tested in insights_test.dart; here a recording one stands in, to see that
/// every call site reports the right thing and nothing it must not.
ProviderContainer _container(
  RecordingInsightsTracker insights, {
  bool signedIn = false,
}) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'persisted' : null),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      checkoutRepositoryProvider.overrideWithValue(FakeCheckoutRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      insightsTrackerProvider.overrideWithValue(insights),
    ],
  );
  addTearDown(container.dispose);
  container.listen(cartControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  container.listen(checkoutControllerProvider, (_, __) {});
  container.listen(wishlistControllerProvider, (_, __) {});
  return container;
}

const _address = <String, dynamic>{
  'firstname': 'Layla',
  'lastname': 'Hassan',
  'telephone': '0500000000',
  'street': ['1 Marina Walk'],
  'city': 'Dubai',
  'country_code': 'AE',
};

void main() {
  group('a cart add', () {
    test('is reported with its SKU and quantity', () async {
      final insights = RecordingInsightsTracker();
      final container = _container(insights);

      await container
          .read(cartControllerProvider.notifier)
          .addToCart(sku: 'CHANEL-COCO', quantity: 2);

      expect(insights.calls, ['cart:CHANEL-COCO x2']);
    });

    test('is not reported when the add fails', () async {
      final insights = RecordingInsightsTracker();
      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          cartRepositoryProvider.overrideWithValue(_FailingCartRepository()),
          insightsTrackerProvider.overrideWithValue(insights),
        ],
      );
      addTearDown(container.dispose);
      container.listen(cartControllerProvider, (_, __) {});
      container.listen(authControllerProvider, (_, __) {});

      await expectLater(
        container
            .read(cartControllerProvider.notifier)
            .addToCart(sku: 'CHANEL-COCO'),
        throwsA(isA<StateError>()),
      );
      expect(insights.calls, isEmpty);
    });

    test('a tracker that breaks never fails the add', () async {
      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
          insightsTrackerProvider.overrideWith((ref) => throw StateError('no tracker')),
        ],
      );
      addTearDown(container.dispose);
      container.listen(cartControllerProvider, (_, __) {});
      container.listen(authControllerProvider, (_, __) {});

      await container
          .read(cartControllerProvider.notifier)
          .addToCart(sku: 'CHANEL-COCO');
      expect(container.read(cartControllerProvider).itemCount, 1);
    });
  });

  group('the wishlist', () {
    Future<ProviderContainer> signedIn(RecordingInsightsTracker insights) async {
      final container = _container(insights, signedIn: true);
      for (var i = 0; i < 20; i++) {
        await pumpEventQueue();
        if (container.read(authControllerProvider).isAuthenticated) break;
      }
      expect(container.read(authControllerProvider).isAuthenticated, isTrue);
      return container;
    }

    test('an add is reported, and the removal that follows is not', () async {
      final insights = RecordingInsightsTracker();
      final container = await signedIn(insights);
      final wishlist = container.read(wishlistControllerProvider.notifier);

      expect(await wishlist.toggle('SKU-A'), isTrue);
      expect(insights.calls, ['wishlist:SKU-A']);

      await wishlist.toggle('SKU-A'); // out again
      expect(insights.calls, ['wishlist:SKU-A']);
    });

    test('a guest who is sent to sign in reports nothing', () async {
      final insights = RecordingInsightsTracker();
      final container = _container(insights);
      await pumpEventQueue();

      expect(await container.read(wishlistControllerProvider.notifier).toggle('SKU-A'), isFalse);
      expect(insights.calls, isEmpty);
    });
  });

  group('an order', () {
    test('is reported with its lines once it is placed, not before', () async {
      final insights = RecordingInsightsTracker();
      final container = _container(insights);
      await container
          .read(cartControllerProvider.notifier)
          .addToCart(sku: 'SKU1', quantity: 3);
      insights.calls.clear();

      final checkout = container.read(checkoutControllerProvider.notifier);
      expect(
        await checkout.submitAddress(
          email: 'guest@example.com',
          shippingAddress: const {'address': _address},
          lastname: 'Hassan',
          telephone: '0500000000',
          isGuest: true,
        ),
        isTrue,
      );
      expect(insights.calls, isEmpty);

      final result = await checkout.placeOrder();

      expect(result, isNotNull);
      expect(insights.calls, ['order:SKU1 x3']);
      // the cart is empty by now: the lines were read before it was cleared
      expect(container.read(cartControllerProvider).cart.items, isEmpty);
    });
  });

  group('a tap on a product in a list', () {
    testWidgets('is reported, and the product page still opens', (tester) async {
      final insights = RecordingInsightsTracker();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => openProduct(
                  context,
                  const Product(sku: 'SKU-TAP', name: 'Tapped', urlKey: 'tapped'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/product/:urlKey',
            builder: (_, state) =>
                Scaffold(body: Text('page ${state.pathParameters['urlKey']}')),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [insightsTrackerProvider.overrideWithValue(insights)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(insights.calls, ['click:SKU-TAP']);
      expect(find.text('page tapped'), findsOneWidget);
    });

    testWidgets('opens the page when there is no tracker to tell', (tester) async {
      // no ProviderScope above the tap at all
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => openProduct(
                  context,
                  const Product(sku: 'SKU-TAP', name: 'Tapped', urlKey: 'tapped'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/product/:urlKey',
            builder: (_, state) =>
                Scaffold(body: Text('page ${state.pathParameters['urlKey']}')),
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('page tapped'), findsOneWidget);
    });
  });
}

/// A cart that refuses every add.
class _FailingCartRepository extends FakeCartRepository {
  @override
  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    bool throwOnUserError = true,
  }) async => throw StateError('refused');
}
