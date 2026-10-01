import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/widgets/cart_summary_card.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../marketplace/marketplace_harness.dart';

/// What a shopper does on the cart (Figma 16): change a quantity, remove a line,
/// select lines and remove them together, apply a coupon — and what the summary
/// and the pinned bar say about it.

/// A cart that answers each change with its new state, like the store.
class _LiveCart extends FakeCartRepository {
  _LiveCart(this.cart);

  Cart cart;
  final List<String> updates = [];
  final List<String> removed = [];
  String? coupon;

  @override
  Future<Cart> getCart(String cartId) async => cart;

  Cart _with({List<CartItem>? items, CartTotals? totals}) => cart = Cart(
    id: cart.id,
    items: items ?? cart.items,
    totals: totals ?? cart.totals,
    totalQuantity: (items ?? cart.items).fold(0, (s, i) => s + i.quantity),
  );

  @override
  Future<Cart> updateItem(String cartId, String uid, int quantity) async {
    updates.add('$uid=$quantity');
    return _with(
      items: [
        for (final i in cart.items)
          if (i.uid == uid)
            CartItem(
              uid: i.uid,
              sku: i.sku,
              name: i.name,
              quantity: quantity,
              unitPrice: i.unitPrice,
              originalUnitPrice: i.originalUnitPrice,
              rowTotal: i.unitPrice == null
                  ? null
                  : aed(i.unitPrice!.amount * quantity),
              options: i.options,
              seller: i.seller,
            )
          else
            i,
      ],
    );
  }

  @override
  Future<Cart> removeItem(String cartId, String uid) async {
    removed.add(uid);
    return _with(items: cart.items.where((i) => i.uid != uid).toList());
  }

  @override
  Future<Cart> applyCoupon(String cartId, String code) async {
    coupon = code;
    return _with(
      totals: CartTotals(
        subtotal: cart.totals.subtotal,
        shipping: cart.totals.shipping,
        discount: aed(20),
        appliedCoupon: code,
        grandTotal: aed(533),
      ),
    );
  }

  @override
  Future<Cart> removeCoupon(String cartId) async {
    coupon = null;
    return _with(
      totals: CartTotals(
        subtotal: cart.totals.subtotal,
        shipping: cart.totals.shipping,
        grandTotal: aed(553),
      ),
    );
  }
}

void main() {
  setUpAll(loadAppFonts);

  final l10n = lookupAppLocalizations(const Locale('en'));

  Future<_LiveCart> pump(
    WidgetTester tester, {
    Cart? start,
    Map<String, String>? cmsBlocks,
  }) async {
    phoneView(tester, height: 1500);
    final repo = _LiveCart(start ?? twoStoreCart('guest-1'));
    await tester.pumpWidget(
      marketplaceHarness(
        locale: 'en',
        location: AppRoutes.cart,
        cartRepository: repo,
        cmsBlocks: cmsBlocks,
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  group('a line', () {
    testWidgets('the stepper changes its quantity', (tester) async {
      final repo = await pump(tester);

      // The sofa (1) → 2; the chair (2) → 1.
      await tester.tap(find.byIcon(HubIcons.plus).first);
      await tester.pumpAndSettle();
      expect(repo.updates, ['i-sofa=2']);

      await tester.tap(find.byIcon(HubIcons.minus).at(1));
      await tester.pumpAndSettle();
      expect(repo.updates, ['i-sofa=2', 'i-chair=1']);
    });

    testWidgets('minus on the last unit removes the line', (tester) async {
      final repo = await pump(tester);

      await tester.tap(find.byIcon(HubIcons.minus).first);
      await tester.pumpAndSettle();
      expect(repo.removed, ['i-sofa']);
      expect(find.text('Corner Sofa Bed'), findsNothing);
    });

    testWidgets('Remove drops the line, and the count follows', (tester) async {
      final repo = await pump(tester);
      expect(find.text('4 items · 2 stores'), findsOneWidget);

      await tester.tap(find.text(l10n.cartRemove).last);
      await tester.pumpAndSettle();
      // The dress is loly store's only line: its card and the count go too.
      expect(repo.removed, ['i-dress']);
      expect(find.text('loly store'), findsNothing);
      expect(find.text('3 items · 1 store'), findsOneWidget);
    });
  });

  group('Select', () {
    testWidgets('ticks lines and removes the ticked ones together', (
      tester,
    ) async {
      final repo = await pump(tester);

      // Not selecting: no tick boxes, the checkout bar.
      expect(find.byIcon(HubIcons.square), findsNothing);
      expect(find.text(l10n.cartCheckout), findsOneWidget);

      await tester.tap(find.text(l10n.cartSelect));
      await tester.pumpAndSettle();
      expect(find.text(l10n.actionCancel), findsOneWidget);
      expect(find.text(l10n.cartSelectedCount(0)), findsOneWidget);
      expect(find.byIcon(HubIcons.square), findsNWidgets(3));
      // The bar offers Remove (off while nothing is ticked), not Checkout.
      expect(find.text(l10n.cartCheckout), findsNothing);
      final off = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, l10n.cartRemoveSelected(0)),
      );
      expect(off.onPressed, isNull);

      // Tapping a line ticks it.
      await tester.tap(find.text('Corner Sofa Bed'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.cartSelectedCount(1)), findsOneWidget);
      expect(find.byIcon(HubIcons.squareCheck), findsOneWidget);

      await tester.tap(find.text(l10n.cartSelectAll));
      await tester.pumpAndSettle();
      expect(find.text(l10n.cartSelectedCount(3)), findsOneWidget);
      expect(find.text(l10n.cartSelectNone), findsOneWidget);

      // Untick the dress, then remove the sofa and the chair.
      await tester.tap(find.text('Floral Print Corset-Waist Tie Dress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cartRemoveSelected(2)));
      await tester.pumpAndSettle();

      expect(repo.removed, ['i-sofa', 'i-chair']);
      expect(find.text('Corner Sofa Bed'), findsNothing);
      expect(find.text('Floral Print Corset-Waist Tie Dress'), findsOneWidget);
      // Back to the normal bar.
      expect(find.text(l10n.cartSelect), findsOneWidget);
      expect(find.text(l10n.cartCheckout), findsOneWidget);
    });

    for (final locale in const ['en', 'ar']) {
      testWidgets('selection mode renders ($locale)', (tester) async {
        phoneView(tester, height: 1316);
        final key = GlobalKey();
        await tester.pumpWidget(
          marketplaceHarness(
            locale: locale,
            location: AppRoutes.cart,
            cartRepository: _LiveCart(twoStoreCart('guest-1')),
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        final l = lookupAppLocalizations(Locale(locale));
        await tester.tap(find.text(l.cartSelect));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Corner Sofa Bed'));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'cart_select_mode_$locale');
        expect(find.text(l.cartSelectedCount(1)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('removing everything ends on the empty cart', (tester) async {
      await pump(tester);
      await tester.tap(find.text(l10n.cartSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cartSelectAll));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cartRemoveSelected(3)));
      await tester.pumpAndSettle();

      expect(find.text(l10n.cartEmptyTitle), findsOneWidget);
      expect(find.text(l10n.cartSelect), findsNothing);
    });

    testWidgets('Cancel leaves selection mode with nothing ticked', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text(l10n.cartSelect));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Corner Sofa Bed'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.actionCancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.cartSelect), findsOneWidget);
      expect(find.byIcon(HubIcons.squareCheck), findsNothing);

      // Selecting again starts clean.
      await tester.tap(find.text(l10n.cartSelect));
      await tester.pumpAndSettle();
      expect(find.text(l10n.cartSelectedCount(0)), findsOneWidget);
    });
  });

  group('the coupon', () {
    testWidgets('Apply sends the code; the cart names it, and × removes it', (
      tester,
    ) async {
      final repo = await pump(tester);
      expect(find.text(l10n.cartCouponLabel), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'SAVE20');
      await tester.tap(find.text(l10n.cartApply));
      await tester.pumpAndSettle();

      expect(repo.coupon, 'SAVE20');
      expect(find.text(l10n.cartCouponApplied('SAVE20')), findsOneWidget);
      // The summary has the line, and the total came down by the discount.
      expect(find.text(l10n.cartPromoCode('SAVE20')), findsOneWidget);
      expect(find.text('− AED 20'), findsNWidgets(2));
      expect(find.text('AED 533'), findsNWidgets(2));

      await tester.tap(find.byIcon(HubIcons.x));
      await tester.pumpAndSettle();
      expect(repo.coupon, isNull);
      expect(find.text(l10n.cartCouponApplied('SAVE20')), findsNothing);
    });
  });

  group('the summary', () {
    testWidgets('"You save" adds up the discounted lines', (tester) async {
      await pump(tester);

      // The sofa AED 500 → 425 and two chairs AED 40 → 34: 75 + 12.
      expect(find.text(l10n.cartYouSave), findsOneWidget);
      expect(find.text('− AED 87'), findsOneWidget);
      expect(find.text(l10n.cartShippingEstimated), findsOneWidget);
      expect(find.text('AED 10'), findsOneWidget);
    });

    testWidgets('no savings line without a discounted line', (tester) async {
      final cart = twoStoreCart('guest-1');
      await pump(
        tester,
        start: Cart(
          id: cart.id,
          totalQuantity: cart.totalQuantity,
          totals: cart.totals,
          items: [
            for (final i in cart.items)
              CartItem(
                uid: i.uid,
                sku: i.sku,
                name: i.name,
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                rowTotal: i.rowTotal,
                seller: i.seller,
              ),
          ],
        ),
      );
      expect(find.text(l10n.cartYouSave), findsNothing);
    });

    test('cartSavings: regular minus charged, times the quantity', () {
      expect(cartSavings(twoStoreCart('c')), aed(87));
      expect(cartSavings(const Cart(id: 'c')), isNull);
    });

    testWidgets('the shipping line is "calculated" until a method is chosen', (
      tester,
    ) async {
      final cart = twoStoreCart('guest-1');
      await pump(
        tester,
        start: Cart(
          id: cart.id,
          totalQuantity: cart.totalQuantity,
          items: cart.items,
          totals: CartTotals(subtotal: aed(543), grandTotal: aed(543)),
        ),
      );
      expect(find.text(l10n.cartDeliveryCalculated), findsOneWidget);
    });
  });

  group('the trust ticks', () {
    const block =
        '<div class="hm-trust">'
        '<div class="hm-trust__item"><span class="hm-trust__title">Easy Returns'
        '</span><span class="hm-trust__text">14-day return policy</span></div>'
        '<div class="hm-trust__item"><span class="hm-trust__title">Trusted '
        'Sellers</span></div>'
        '</div>';

    testWidgets('are the storefront\'s own trust items', (tester) async {
      await pump(tester, cmsBlocks: {'hm_home_trust': block});

      expect(find.text('Easy Returns · 14-day return policy'), findsOneWidget);
      expect(find.text('Trusted Sellers'), findsOneWidget);
      expect(find.byIcon(HubIcons.check), findsNWidgets(2));
    });

    testWidgets('are left out when the store has no such block', (
      tester,
    ) async {
      await pump(tester, cmsBlocks: const {});
      expect(find.byIcon(HubIcons.check), findsNothing);
    });
  });

  testWidgets('Checkout opens checkout with the cart total beside it', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(l10n.cartTotal), findsOneWidget);
    expect(find.text('AED 553'), findsNWidgets(2));

    await tester.tap(find.text(l10n.cartCheckout));
    await tester.pumpAndSettle();
    expect(find.text(AppRoutes.checkout), findsOneWidget);
  });
}
