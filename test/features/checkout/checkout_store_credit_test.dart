import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/checkout_credit_controller.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/store_credit_row.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';

import '../../support/fakes.dart';
import '../../support/store_credit_fakes.dart';
import 'checkout_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

/// The checkout cart whose total follows the credit on it, the way Magento
/// recollects the quote once Vnecoms Credit has been applied.
class _CreditCartRepository extends CheckoutCartRepository {
  _CreditCartRepository(this.credit);

  final FakeStoreCreditRepository credit;

  @override
  Future<Cart> getCart(String cartId) async {
    final cart = checkoutCart(cartId);
    return Cart(
      id: cart.id,
      items: cart.items,
      totalQuantity: cart.totalQuantity,
      totals: CartTotals(
        subtotal: cart.totals.subtotal,
        grandTotal: aed(credit.grandTotalNow),
      ),
    );
  }
}

/// COD and the Zero Subtotal method Magento offers once nothing is left to
/// pay, both offline.
FakeCheckoutRepository _checkout() => FakeCheckoutRepository(
  shippingMethods: kShippingMethods,
  paymentMethods: const [
    PaymentMethodOption(code: 'cashondelivery', title: 'Cash on delivery'),
  ],
  grandTotal: aed(553),
  orderResult: const PlaceOrderResult(orderNumber: '000000248'),
);

Future<void> _toPayment(
  WidgetTester tester, {
  required FakeStoreCreditRepository credit,
  FakeCheckoutRepository? repository,
  String locale = 'en',
  bool signedIn = true,
  bool deployed = true,
  bool creditOn = true,
  double height = 1040,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    checkoutHarness(
      locale: locale,
      repository: repository ?? _checkout(),
      signedIn: signedIn,
      boundary: boundary,
      hubApp: accountHubApp(deployed: deployed, storeCredit: creditOn),
      cartRepository: _CreditCartRepository(credit),
      overrides: [storeCreditRepositoryProvider.overrideWithValue(credit)],
    ),
  );
  await tester.pumpAndSettle();
  if (!signedIn) {
    await fillGuestAddress(tester);
    await tapText(tester, 'Continue to shipping method');
  }
  await tapText(
    tester,
    locale == 'ar' ? 'المتابعة للدفع' : 'Continue to payment',
  );
}

Finder get _switch => find.descendant(
  of: find.byType(CheckoutStoreCreditRow),
  matching: find.byType(Switch),
);

void main() {
  setUpAll(loadCheckoutFonts);

  group('18 Payment · Use my credit', () {
    testWidgets('offers the balance while the customer can spend it', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit());
      await _toPayment(tester, credit: credit);

      expect(find.text('Use my credit'), findsOneWidget);
      expect(find.textContaining('AED 120'), findsOneWidget);
      expect(find.textContaining('available'), findsOneWidget);
      expect(tester.widget<Switch>(_switch).value, isFalse);
      // Read when the step opened: the shipping method is on the cart.
      expect(credit.calls, ['fetchCartCredit:customer-1']);
      expect(find.text('Store credit'), findsNothing);
    });

    testWidgets(
      'turning it on uses what the order allows and re-reads the totals',
      (tester) async {
        final credit = FakeStoreCreditRepository(
          cartCredit: sampleCartCredit(),
        );
        final checkout = _checkout();
        await _toPayment(tester, credit: credit, repository: checkout);

        await tester.tap(_switch);
        await tester.pumpAndSettle();

        expect(credit.calls, [
          'fetchCartCredit:customer-1',
          'apply:customer-1:120.0',
        ]);
        expect(tester.widget<Switch>(_switch).value, isTrue);
        expect(find.textContaining('used on this order'), findsOneWidget);
        // The summary carries the credit and the total Magento now charges.
        expect(find.text('Store credit'), findsOneWidget);
        expect(find.text('−AED 120'), findsOneWidget);
        expect(find.text('AED 433'), findsOneWidget);
        // Cash on delivery still pays for the rest: no method change.
        expect(checkout.calls.where((c) => c.startsWith('setPaymentMethod')), [
          'setPaymentMethod:cashondelivery',
        ]);

        // Review shows the same credit, and Place order quotes the new total.
        await tapText(tester, 'Review order');
        expect(find.text('Store credit'), findsOneWidget);
        expect(find.text('Place order · AED 433'), findsOneWidget);
      },
    );

    testWidgets('turning it off gives the credit back', (tester) async {
      final credit = FakeStoreCreditRepository(
        cartCredit: sampleCartCredit(applied: 120),
      );
      await _toPayment(tester, credit: credit);
      expect(tester.widget<Switch>(_switch).value, isTrue);
      expect(find.text('Store credit'), findsOneWidget);

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      expect(credit.calls.last, 'remove:customer-1');
      expect(tester.widget<Switch>(_switch).value, isFalse);
      expect(find.text('Store credit'), findsNothing);
      expect(find.text('AED 553'), findsOneWidget);
    });

    testWidgets(
      'credit that covers the order moves payment to Zero Subtotal and back',
      (tester) async {
        final credit = FakeStoreCreditRepository(
          cartCredit: sampleCartCredit(balance: 600, maxApplicable: 553),
        );
        final checkout = _checkout();
        await _toPayment(tester, credit: credit, repository: checkout);

        await tester.tap(_switch);
        await tester.pumpAndSettle();
        expect(credit.calls.last, 'apply:customer-1:553.0');
        expect(checkout.calls.last, 'setPaymentMethod:free');
        expect(find.text('No Payment Information Required'), findsOneWidget);
        expect(find.text('Cash on delivery'), findsNothing);

        await tester.tap(_switch);
        await tester.pumpAndSettle();
        expect(credit.calls.last, 'remove:customer-1');
        expect(checkout.calls.last, 'setPaymentMethod:cashondelivery');
        expect(find.text('Cash on delivery'), findsOneWidget);
      },
    );

    testWidgets('a refusal says why and leaves the order as it was', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit());
      await _toPayment(tester, credit: credit);
      credit.nextError = kCreditRefused;

      await tester.tap(_switch);
      await tester.pumpAndSettle();

      expect(
        find.text('You can use at most AED 120.00 of store credit.'),
        findsOneWidget,
      );
      expect(tester.widget<Switch>(_switch).value, isFalse);
      expect(find.text('Store credit'), findsNothing);
      expect(find.text('AED 553'), findsOneWidget);
    });

    testWidgets('reads the credit again each time the step opens', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit());
      await _toPayment(tester, credit: credit);
      await tester.tap(find.byIcon(HubIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tapText(tester, 'Continue to payment');
      expect(credit.calls, [
        'fetchCartCredit:customer-1',
        'fetchCartCredit:customer-1',
      ]);
    });

    for (final (name, cartCredit) in [
      (
        'the customer group may not spend credit',
        sampleCartCredit(canUse: false),
      ),
      ('there is no credit', sampleCartCredit(balance: 0, maxApplicable: 0)),
    ]) {
      testWidgets('not offered when $name', (tester) async {
        await _toPayment(
          tester,
          credit: FakeStoreCreditRepository(cartCredit: cartCredit),
        );
        expect(find.byType(CheckoutStoreCreditRow), findsNothing);
        expect(find.text('Cash on delivery'), findsOneWidget);
      });
    }

    testWidgets('Build 1: nothing asked of a server without the module', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit());
      await _toPayment(tester, credit: credit, deployed: false);
      expect(find.byType(CheckoutStoreCreditRow), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('nothing asked while the store_credit switch is off', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit());
      await _toPayment(tester, credit: credit, creditOn: false);
      expect(find.byType(CheckoutStoreCreditRow), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('a guest is never offered credit', (tester) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit());
      await _toPayment(tester, credit: credit, signedIn: false, height: 1400);
      expect(find.byType(CheckoutStoreCreditRow), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('a server lacking the account module keeps checkout as is', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(cartCredit: sampleCartCredit())
        ..missing = true;
      await _toPayment(tester, credit: credit);
      expect(find.byType(CheckoutStoreCreditRow), findsNothing);
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  test('uses max_applicable rounded down to whole fils', () {
    double amount(double max) => CheckoutCreditController.usableAmount(
      sampleCartCredit(maxApplicable: max),
    );
    expect(amount(120), 120);
    expect(amount(45.5), 45.5);
    expect(amount(0.29), 0.29);
    expect(amount(119.996), 119.99);
  });

  group('18 Payment with credit renders', () {
    for (final locale in ['en', 'ar']) {
      for (final applied in [false, true]) {
        final name =
            'checkout_18_payment_credit${applied ? '_on' : ''}_$locale';
        testWidgets(name, (tester) async {
          final key = GlobalKey();
          await _toPayment(
            tester,
            credit: FakeStoreCreditRepository(
              cartCredit: sampleCartCredit(applied: applied ? 120 : 0),
            ),
            locale: locale,
            height: 844,
            boundary: key,
          );
          await capture(tester, key, name);
          expect(
            Directionality.of(
              tester.element(find.byType(CheckoutStoreCreditRow)),
            ),
            locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
