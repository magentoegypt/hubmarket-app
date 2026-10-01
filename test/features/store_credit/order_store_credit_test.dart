import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';

import '../../support/fonts.dart';
import '../../support/store_credit_fakes.dart';
import 'store_credit_harness.dart';

const _order = CustomerOrder(
  number: '000000248',
  status: 'Pending',
  date: '2026-09-28 10:42:00',
  id: 'MjQ4',
  total: Money(amount: 530, currency: 'AED'),
  subtotal: Money(amount: 543, currency: 'AED'),
  shippingAmount: Money(amount: 10, currency: 'AED'),
  lines: [
    OrderLine(
      name: 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      price: Money(amount: 50, currency: 'AED'),
    ),
  ],
);

const _placed = OrderPlacedArgs(
  orderNumber: '000000248',
  firstName: 'Sara',
  total: Money(amount: 530, currency: 'AED'),
  payment: PaymentMethodOption(
    code: 'cashondelivery',
    title: 'Cash on delivery',
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen,
  FakeStoreCreditRepository credit, {
  String locale = 'en',
  bool deployed = true,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = const Size(390, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    storeCreditHarness(
      screen: screen,
      credit: credit,
      locale: locale,
      hubApp: creditHubApp(deployed: deployed),
      boundary: boundary,
    ),
  );
  await tester.pumpAndSettle();
}

FakeStoreCreditRepository _usedCredit() =>
    FakeStoreCreditRepository(orderCredits: {'000000248': aedCredit(23)});

void main() {
  setUpAll(loadAppFonts);

  group('Order detail', () {
    testWidgets('lists the store credit the order used', (tester) async {
      final credit = _usedCredit();
      await _pump(tester, const OrderDetailScreen(order: _order), credit);
      expect(find.text('Store credit'), findsOneWidget);
      expect(find.text('−AED 23'), findsOneWidget);
      expect(credit.calls, ['fetchOrderCredit:000000248']);
    });

    testWidgets('no line for an order paid without credit', (tester) async {
      final credit = FakeStoreCreditRepository();
      await _pump(tester, const OrderDetailScreen(order: _order), credit);
      expect(find.text('Store credit'), findsNothing);
      expect(credit.calls, ['fetchOrderCredit:000000248']);
    });

    testWidgets('a guest order is never looked up', (tester) async {
      final credit = _usedCredit();
      const guestOrder = CustomerOrder(
        number: '000000248',
        status: 'Pending',
        date: '2026-09-28 10:42:00',
        placedAsGuest: true,
      );
      await _pump(tester, const OrderDetailScreen(order: guestOrder), credit);
      expect(find.text('Store credit'), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('Build 1: no lookup on a server without the module', (
      tester,
    ) async {
      final credit = _usedCredit();
      await _pump(
        tester,
        const OrderDetailScreen(order: _order),
        credit,
        deployed: false,
      );
      expect(find.text('Store credit'), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('a failed lookup leaves the order as it was', (tester) async {
      final credit = _usedCredit()..missing = true;
      await _pump(tester, const OrderDetailScreen(order: _order), credit);
      expect(find.text('Store credit'), findsNothing);
      expect(find.text('AED 530'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('19 Order placed', () {
    testWidgets('says how much store credit paid', (tester) async {
      final credit = _usedCredit();
      await _pump(tester, const OrderSuccessScreen(args: _placed), credit);
      expect(
        find.textContaining('paid with your store credit'),
        findsOneWidget,
      );
      expect(find.textContaining('AED 23'), findsOneWidget);
      // The rest is paid on delivery, as before.
      expect(find.textContaining('AED 530'), findsOneWidget);
    });

    testWidgets('no line when the order used none', (tester) async {
      await _pump(
        tester,
        const OrderSuccessScreen(args: _placed),
        FakeStoreCreditRepository(),
      );
      expect(find.textContaining('store credit'), findsNothing);
    });

    for (final locale in ['en', 'ar']) {
      testWidgets('19 with store credit renders ($locale)', (tester) async {
        final key = GlobalKey();
        await _pump(
          tester,
          const OrderSuccessScreen(args: _placed),
          _usedCredit(),
          locale: locale,
          boundary: key,
        );
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        await captureScreen(tester, key, '19_order_placed_credit_$locale');
        expect(
          Directionality.of(tester.element(find.byType(OrderSuccessScreen))),
          locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
