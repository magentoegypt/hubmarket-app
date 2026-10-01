import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';

import '../../support/hubapp_fakes.dart';
import '../../support/store_credit_fakes.dart';
import '../marketplace/marketplace_harness.dart' show twoStoreCart;
import '../store_credit/store_credit_harness.dart';
import 'checkout_harness.dart';

/// Figma 16's cart: three lines from MIA CO and loly store.
class _TwoStoreCart extends CheckoutCartRepository {
  @override
  Future<Cart> getCart(String cartId) async => twoStoreCart(cartId);
}

void main() {
  group('placedPackagesOf', () {
    test('one package per store, with its units, in the cart order', () {
      final packages = placedPackagesOf(twoStoreCart('c-1'));

      expect(packages.map((p) => p.seller?.name), ['MIA CO', 'loly store']);
      // The sofa and two chairs; the dress.
      expect(packages.map((p) => p.itemCount), [3, 1]);
      // One photo per line: the sofa and the chair; the dress.
      expect(packages.map((p) => p.imageUrls.length), [2, 1]);
    });

    test('none when no line names a seller (Build 1)', () {
      expect(placedPackagesOf(checkoutCart('c-1')), isEmpty);
    });
  });

  Future<void> placeOrder(
    WidgetTester tester, {
    required CheckoutCartRepository cart,
    required HubAppState hubApp,
  }) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      checkoutHarness(
        locale: 'en',
        repository: checkoutRepository(),
        signedIn: true,
        cartRepository: cart,
        hubApp: hubAppOverride(hubApp),
      ),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue to payment');
    await tapText(tester, 'Review order');
    await tapText(tester, 'Place order · AED 553');
    expect(find.byType(OrderSuccessScreen), findsOneWidget);
  }

  testWidgets('Order placed lists the stores the order ships from', (
    tester,
  ) async {
    await placeOrder(
      tester,
      cart: _TwoStoreCart(),
      hubApp: const HubAppState.available(kSampleHmAppConfig),
    );

    expect(find.text('Arriving in 2 packages'), findsOneWidget);
    expect(find.text('MIA CO'), findsOneWidget);
    expect(find.text('loly store'), findsOneWidget);
    // Figma 19: a thumbnail per line at the end of its store's row — three
    // lines, with the two store logos.
    expect(find.byType(HubImage), findsNWidgets(3 + 2));

    // Track order opens this order.
    await tapText(tester, 'Track order');
    expect(find.text('route /orders/000000248'), findsOneWidget);
  });

  testWidgets('without sellers there is no package list (Build 1)', (
    tester,
  ) async {
    await placeOrder(
      tester,
      cart: CheckoutCartRepository(),
      hubApp: const HubAppState.unavailable(),
    );

    expect(find.textContaining('Arriving in'), findsNothing);
  });

  testWidgets('lines without a seller make a numbered package', (tester) async {
    final cart = twoStoreCart('c-1');
    final packages = placedPackagesOf(
      Cart(
        id: cart.id,
        items: [
          ...cart.items,
          const CartItem(uid: 'i-x', sku: 'X', name: 'Mystery', quantity: 2),
        ],
      ),
    );
    expect(packages.map((p) => p.seller?.name), ['MIA CO', 'loly store', null]);

    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      storeCreditHarness(
        screen: OrderSuccessScreen(
          args: OrderPlacedArgs(orderNumber: '000000248', packages: packages),
        ),
        credit: FakeStoreCreditRepository(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arriving in 3 packages'), findsOneWidget);
    expect(find.text('Package 3'), findsOneWidget);
  });
}
