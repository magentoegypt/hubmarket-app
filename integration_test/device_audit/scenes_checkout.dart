import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/payment_failed_sheet.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../test/support/fakes.dart';
import '../../test/support/store_credit_fakes.dart';
import 'audit_scene.dart';
import 'checkout_fixtures.dart';
import 'harness.dart';

/// Cart and checkout: D16 Cart, D17 Shipping, D17a Guest checkout, D18 Payment, D18b Review, D19 Order placed, F_S1 Empty cart, F_S5 Payment failed.
///
/// One scene per frame state, ported from the widget test that renders it (see
/// docs/ui-audit.md, `PAIRS` in tool/ui_audit/pairs.py names the captures):
///
/// * D16 - test/features/marketplace/marketplace_render_test.dart (`16 cart by
///   store`), the cart tab of a guest with a cart on the device;
/// * F_S1 - test/features/cart/cart_empty_render_test.dart;
/// * D17 / D18 / D18b - test/features/checkout/checkout_render_test.dart: a
///   signed-in customer with HubApp (lines grouped by store, AED 600 free
///   shipping, AED 120 of store credit), the same Continue taps as the test;
/// * D17a - the same file, a guest on Build 1 who fills the form in;
/// * D19 - the same file; see the scene for how it is mounted;
/// * F_S5 - test/features/checkout/payment_failed_sheet_test.dart.
List<AuditScene> scenes() => [
  // Figma 16: the cart grouped by store - 4 items, 2 stores, the free-shipping
  // bar, the coupon, the summary and trust ticks, the pinned Total / Checkout
  // bar above the tab bar. A tab root; the guest cart comes from the device.
  // Two scrolls, not the one the frame's height gives: the header, the pinned
  // bar and the tab bar leave the list about 500 dp of the phone's 820.
  AuditScene(
    frame: 'D16_cart',
    name: 'default',
    screen: (_) => const CartScreen(),
    signedIn: false,
    pushed: false,
    scrolls: 2,
    setup: (locale) => AuditSetup(
      overrides: cartTabOverrides(
        cart: FixedCartRepository((id) => cartByStore(locale, id)),
        freeShipping: 600,
        cmsBlocks: {'hm_home_trust': cartTrustBlock(locale)},
      ),
    ),
  ),

  // Figma S1: nothing in the cart (Build 1, no free-shipping figure).
  AuditScene(
    frame: 'F_S1_empty_cart',
    name: 'default',
    screen: (_) => const CartScreen(),
    signedIn: false,
    pushed: false,
    setup: (_) => AuditSetup(
      hubApp: const HubAppState.unavailable(),
      overrides: cartTabOverrides(cart: FakeCartRepository()),
    ),
  ),

  // Figma 17: step 1 for a signed-in customer - "Ship to" with the default
  // saved address (sent on its own once the address book has loaded), the two
  // shipping methods and the packages the order ships in.
  AuditScene(
    frame: 'D17_checkout_ship',
    name: 'default',
    screen: (_) => const CheckoutScreen(),
    setup: _customerCheckout,
  ),

  // Figma 17a: step 1 for a guest - contact, the address form filled in, and
  // the "You already have an account with us" card the store's answer to the
  // email brings. Build 1: no store on the lines.
  AuditScene(
    frame: 'D17a_checkout_guest',
    name: 'default',
    screen: (_) => const CheckoutScreen(),
    signedIn: false,
    scrolls: 1,
    setup: (_) => AuditSetup(
      hubApp: const HubAppState.unavailable(),
      overrides: checkoutOverrides(
        cart: FixedCartRepository(checkoutCart),
        signedIn: false,
        registeredEmail: 'sara.ahmed@gmail.com',
      ),
    ),
    act: (tester, locale) async {
      await fillGuestAddress(tester);
      // No field keeps the focus ring the last tap left it (the frame draws the
      // email focused as a state sample; the layout is what is compared).
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, 400);
      // Filling the form scrolled the page down to its last field.
      await scrollToTop(tester);
    },
  ),

  // Figma 18: "Continue to payment" - the methods the app can take, "Use my
  // credit" and the order summary.
  AuditScene(
    frame: 'D18_checkout_pay',
    name: 'default',
    screen: (_) => const CheckoutScreen(),
    scrolls: 1,
    setup: _customerCheckout,
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tapText(tester, l10n.checkoutContinueToPayment);
    },
  ),

  // Figma 18b: payment, then "Review order" - address, method, payment, items
  // by store and totals before Place order.
  AuditScene(
    frame: 'D18b_checkout_review',
    name: 'default',
    screen: (_) => const CheckoutScreen(),
    scrolls: 1,
    setup: _customerCheckout,
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tapText(tester, l10n.checkoutContinueToPayment);
      await tapText(tester, l10n.checkoutReviewOrder);
    },
  ),

  // Figma 19: Order placed. The test taps Place order and lands here through
  // `context.go(AppRoutes.orderSuccess, extra: OrderPlacedArgs(...))`, a route
  // the audit router does not have, so the screen is mounted directly with the
  // arguments checkout builds at that tap: the customer's first name, the order
  // number the store answers, the grand total, the pre-selected cash on
  // delivery and the packages read from the cart's stores (`placedPackagesOf`).
  // `go` leaves nothing beneath it, hence `pushed: false`.
  AuditScene(
    frame: 'D19_order_placed',
    name: 'default',
    screen: (locale) => OrderSuccessScreen(
      args: OrderPlacedArgs(
        orderNumber: '000000248',
        firstName: kSampleCustomer.firstName,
        total: aed(553),
        payment: kCashOnDelivery,
        packages: placedPackagesOf(
          checkoutSellerCart('customer-1', locale: locale),
        ),
      ),
    ),
    pushed: false,
    setup: _customerCheckout,
  ),

  // Figma S5: the "Payment declined" sheet over a blank white page. The test
  // opens it from a button on that page; here the page is bare and the sheet is
  // opened from its context, which leaves the same picture.
  AuditScene(
    frame: 'F_S5_payment_failed',
    name: 'default',
    screen: (_) => const Scaffold(backgroundColor: Colors.white),
    pushed: false,
    act: (tester, locale) async {
      final context = tester.element(find.byType(Scaffold));
      unawaited(
        showPaymentFailedSheet(
          context,
          methodTitle: 'Visa •••• 4242',
          reason: 'insufficient funds (code 51)',
          canTryAnotherMethod: true,
          canPayCashOnDelivery: true,
        ),
      );
      await pumpFor(tester, 600);
    },
  ),
];

/// A signed-in customer checking out with HubApp deployed: the lines grouped by
/// store, the AED 600 free-shipping threshold and AED 120 of store credit
/// (`accountHubApp(deployed: true, storeCredit: true)` in the test).
AuditSetup _customerCheckout(String locale) => AuditSetup(
  hubApp: HubAppState.available(hubAppAccountConfig(storeCredit: true)),
  overrides: checkoutOverrides(
    cart: FixedCartRepository((id) => checkoutSellerCart(id, locale: locale)),
    hubApp: true,
  ),
);
