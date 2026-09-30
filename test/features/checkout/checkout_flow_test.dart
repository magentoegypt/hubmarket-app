import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/backend_capabilities.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/checkout_parts.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/guest_verify_card.dart';

import '../../support/fakes.dart';
import 'checkout_harness.dart';

/// The three-step checkout on screen (Figma 17 → 18 → 18b → 19), driven the
/// way a shopper would, against fake repositories.
void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeCheckoutRepository repo, {
    bool signedIn = false,
    BackendCapabilities capabilities = BackendCapabilities.hubMarket,
  }) async {
    tester.view.physicalSize = const Size(390, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      checkoutHarness(
        locale: 'en',
        repository: repo,
        signedIn: signedIn,
        capabilities: capabilities,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Guest contact + address → Ship to / shipping method.
  Future<void> throughAddress(WidgetTester tester) async {
    await fillGuestAddress(tester);
    await tapText(tester, 'Continue to shipping method');
  }

  testWidgets('a guest gives contact and address first, then a shipping '
      'method', (tester) async {
    final repo = checkoutRepository();
    await mount(tester, repo);

    // 17a: contact before anything else, no shipping choices yet.
    expect(find.text('Contact'), findsOneWidget);
    expect(find.text('Email address'), findsWidgets);
    expect(find.text('Shipping address'), findsOneWidget);
    expect(find.text('Shipping method'), findsNothing);

    await throughAddress(tester);

    // 17: the submitted address and Magento's methods, cheapest selected.
    expect(find.text('Ship to'), findsOneWidget);
    expect(
      find.text('Sara Ahmed · \u2066+971 50 123 4567\u2069'),
      findsOneWidget,
    );
    expect(find.text('Marina Gate 2, Apt 1204, Dubai'), findsOneWidget);
    expect(find.text('Standard delivery'), findsOneWidget);
    expect(find.text('Express delivery'), findsOneWidget);
    expect(find.text('Contact'), findsNothing);
    expect(repo.guestEmail, 'sara.ahmed@gmail.com');
    expect(repo.selectedShippingMethod, 'flatrate|flatrate');
  });

  testWidgets('a guest whose email has an account is offered sign-in', (
    tester,
  ) async {
    await mount(
      tester,
      checkoutRepository(registeredEmail: 'sara.ahmed@gmail.com'),
    );
    await fillGuestAddress(tester);
    expect(find.text('You already have an account with us.'), findsOneWidget);

    await tapText(tester, 'Sign in');
    expect(find.text('route /signin'), findsOneWidget);
  });

  testWidgets('an email without an account gets no prompt', (tester) async {
    await mount(tester, checkoutRepository());
    await fillGuestAddress(tester);
    expect(find.text('You already have an account with us.'), findsNothing);
  });

  testWidgets('steps advance only forward from a complete step, and back walks '
      'them in reverse', (tester) async {
    await mount(tester, checkoutRepository());
    await throughAddress(tester);

    await tapText(tester, 'Continue to payment');
    expect(find.text('Payment method'), findsOneWidget);
    // Only what the app can take: the online method stays out.
    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(find.text('Pay in 4 with Tabby'), findsNothing);
    expect(
      find.text('Pay each store when its package arrives'),
      findsOneWidget,
    );

    await tapText(tester, 'Review order');
    expect(find.text('Review your order'), findsOneWidget);

    // Back: Review → Payment → Shipping (Ship to, not the form again).
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Payment method'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Ship to'), findsOneWidget);

    // A completed step is reachable from the indicator; Review's Edit links
    // return to the step they name.
    await tapText(tester, 'Continue to payment');
    await tapText(tester, 'Review order');
    await tester.tap(
      find.descendant(
        of: find.byType(CheckoutStepIndicator),
        matching: find.text('Shipping'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ship to'), findsOneWidget);
    await tapText(tester, 'Continue to payment');
    await tapText(tester, 'Review order');
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(find.text('Payment method'), findsOneWidget);
  });

  testWidgets('a store offering only online methods says so instead of '
      'leaving a dead button', (tester) async {
    await mount(
      tester,
      FakeCheckoutRepository(
        shippingMethods: kShippingMethods,
        paymentMethods: const [
          PaymentMethodOption(
            code: 'payment_services_paypal_hosted_fields',
            title: 'Credit Card',
            isOnline: true,
          ),
        ],
      ),
    );
    await throughAddress(tester);

    expect(
      find.text('No payment method can be used for this order in the app yet.'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue to payment'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('with guest OTP on, the code is sent once per number and gates '
      'payment until verified', (tester) async {
    final repo = checkoutRepository();
    await mount(
      tester,
      repo,
      capabilities: const BackendCapabilities(guestCheckoutOtp: true),
    );
    await throughAddress(tester);
    int sent() =>
        repo.calls.where((c) => c == 'requestGuestCheckoutOtp').length;

    expect(sent(), 1);
    FilledButton continueButton() => tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue to payment'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(continueButton().onPressed, isNull);

    await tester.enterText(
      find.descendant(
        of: find.byType(GuestVerifyCard),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.pumpAndSettle();
    expect(find.text('Mobile number verified'), findsOneWidget);
    expect(continueButton().onPressed, isNotNull);

    // Payment and back rebuild the card; it must not send another code.
    await tapText(tester, 'Continue to payment');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Mobile number verified'), findsOneWidget);
    expect(sent(), 1);
  });

  testWidgets('"Change" reopens the address, and back returns to Ship to', (
    tester,
  ) async {
    await mount(tester, checkoutRepository());
    await throughAddress(tester);

    await tapText(tester, 'Change');
    expect(find.text('Shipping address'), findsOneWidget);
    expect(find.text('Continue to shipping method'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Ship to'), findsOneWidget);
  });

  testWidgets('review lists every item with its options, quantity and line '
      'total', (tester) async {
    await mount(tester, checkoutRepository());
    await throughAddress(tester);
    await tapText(tester, 'Continue to payment');
    await tapText(tester, 'Review order');

    expect(find.text('Items (4)'), findsOneWidget);
    expect(find.text('Corner Sofa Bed'), findsOneWidget);
    expect(find.text('Colour: Teal · Qty 1'), findsOneWidget);
    expect(find.text('Dining Chair with Gold Metal Legs'), findsOneWidget);
    expect(find.text('Qty 2'), findsOneWidget);
    expect(find.text('AED 68.00'), findsOneWidget);
    expect(find.text('Floral Print Corset-Waist Tie Dress'), findsOneWidget);
    expect(find.text('Size: M · Qty 1'), findsOneWidget);
    // Address, method, payment and the total the order will be charged.
    expect(find.text('Standard delivery · 2–4 working days'), findsOneWidget);
    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(find.text('Total (incl. VAT)'), findsOneWidget);
    expect(find.text('Place order · AED 553.00'), findsOneWidget);
  });

  testWidgets('placing a cash-on-delivery order runs the checkout mutations '
      'in order and lands on Order placed', (tester) async {
    final repo = checkoutRepository();
    await mount(tester, repo);
    await throughAddress(tester);
    await tapText(tester, 'Continue to payment');
    await tapText(tester, 'Review order');
    await tapText(tester, 'Place order · AED 553.00');

    expect(repo.calls, [
      'hasAccount',
      'setGuestEmail',
      'setShippingAddress',
      'setShippingMethod:flatrate|flatrate',
      'setBillingSameAsShipping',
      'setPaymentMethod:cashondelivery',
      'placeOrder',
    ]);
    expect(find.byType(OrderSuccessScreen), findsOneWidget);
    expect(find.text('Order placed!'), findsOneWidget);
    expect(
      find.text(
        'Thank you, Sara. Order #000000248 is confirmed — we’ve emailed your '
        'receipt.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Pay \u2066AED 553.00\u2069 in cash when your order arrives'),
      findsOneWidget,
    );

    // Track order opens this order.
    await tapText(tester, 'Track order');
    expect(find.text('route /orders/000000248'), findsOneWidget);
  });

  testWidgets('a signed-in customer starts on Ship to with the default '
      'address, and Change offers the address book', (tester) async {
    final repo = checkoutRepository();
    await mount(tester, repo, signedIn: true);

    expect(find.text('Contact'), findsNothing);
    expect(find.text('Ship to'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    // By reference: a saved address must not be re-saved as a copy.
    expect(repo.lastAddress, {'customer_address_id': 7});
    expect(repo.calls, isNot(contains('setGuestEmail')));

    await tapText(tester, 'Change');
    expect(find.text('Use a new address'), findsOneWidget);
    expect(find.text('Sara Ahmed'), findsOneWidget);
  });
}
