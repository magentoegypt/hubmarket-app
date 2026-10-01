import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/orders_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/returns_fakes.dart';

/// Renders Figma 21 "My orders" (20:1401 / 52:1961) in English and Arabic to
/// build/test_screens/audit_21_orders_{en,ar}.png, and checks the pieces the
/// frame draws: the chips, one row per store, the actions that fit each order.
Money _aed(double amount) => Money(amount: amount, currency: 'AED');

OrderPackage _package(
  HmSellerSummary store,
  String label,
  String state,
  List<String> uids, {
  bool shipped = false,
}) => OrderPackage(
  seller: store,
  statusCode: state,
  statusLabel: label,
  state: state,
  itemUids: uids,
  shipments: [
    if (shipped) const OrderPackageShipment(id: 's1', number: '000000031'),
  ],
);

OrderLine _line(String name, String uid, HmSellerSummary store) =>
    OrderLine(name: name, quantity: 1, sku: 'SKU-$uid', seller: store, uid: uid);

List<CustomerOrder> _orders(String locale) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  final walmart = seller('walmart', ar ? 'وول مارت' : 'walmart');
  return [
    // Out for delivery at loly store, being prepared at MIA CO.
    CustomerOrder(
      number: 'HM-100248',
      status: ar ? 'قيد التنفيذ' : 'Processing',
      date: '2026-09-28 10:42:00',
      id: 'MjQ4',
      availableActions: const {'CANCEL'},
      invoiceCount: 1,
      total: _aed(553),
      lines: [
        _line('Floral Print Corset-Waist Tie Dress', 'a', loly),
        _line('Corner Sofa Bed', 'b', mia),
        _line('Dining Chair with Gold Metal Legs', 'c', mia),
      ],
      packages: [
        _package(
          loly,
          ar ? 'في الطريق إليك' : 'Out for delivery',
          'processing',
          const ['a'],
          shipped: true,
        ),
        _package(
          mia,
          ar ? 'قيد التجهيز' : 'Processing',
          'new',
          const ['b', 'c'],
        ),
      ],
    ),
    // Delivered by walmart.
    CustomerOrder(
      number: 'HM-100197',
      status: ar ? 'مكتمل' : 'Complete',
      date: '2026-09-14 09:10:00',
      id: 'MTk3',
      availableActions: const {'REORDER'},
      invoiceCount: 1,
      shipmentCount: 1,
      total: _aed(98),
      lines: [
        _line('Tuna', 'd', walmart),
        _line('Cola', 'e', walmart),
        _line('Water', 'f', walmart),
      ],
      packages: [
        _package(
          walmart,
          ar ? 'تم التوصيل' : 'Delivered',
          'complete',
          const ['d', 'e', 'f'],
        ),
      ],
    ),
    // A return open on it.
    CustomerOrder(
      number: 'HM-100150',
      status: ar ? 'مكتمل' : 'Complete',
      date: '2026-09-20 18:30:00',
      id: 'MTUw',
      invoiceCount: 1,
      shipmentCount: 1,
      total: _aed(43),
      lines: [_line('Short Square-Neck T-Shirt', 'g', loly)],
      packages: [
        _package(
          loly,
          ar ? 'تم التوصيل' : 'Delivered',
          'complete',
          const ['g'],
        ),
      ],
    ),
  ];
}

ReturnSummary _openReturn(HmSellerSummary store) => ReturnSummary(
  id: 31,
  number: 'R-000031',
  orderNumber: 'HM-100150',
  createdAt: '2026-09-24T09:00:00Z',
  statusCode: 'pending',
  statusLabel: 'Awaiting store',
  itemCount: 1,
  seller: store,
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('21 My orders ($locale)', (tester) async {
      final key = GlobalKey();
      await pumpAudit(
        tester,
        locale: locale,
        boundary: key,
        screen: const OrdersScreen(),
        account: FakeAccountRepository(orders: _orders(locale)),
        returns: FakeReturnsRepository(
          summaries: [_openReturn(seller('loly', 'loly store'))],
        ),
      );
      await captureScreen(tester, key, 'audit_21_orders_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('21 My orders: what each order offers', (tester) async {
    await pumpAudit(
      tester,
      screen: const OrdersScreen(),
      account: FakeAccountRepository(orders: _orders('en')),
      returns: FakeReturnsRepository(
        summaries: [_openReturn(seller('loly', 'loly store'))],
      ),
    );
    // The frame's four chips (Returns while returns are on).
    for (final chip in ['All', 'In progress', 'Delivered', 'Returns']) {
      expect(find.text(chip), findsOneWidget);
    }
    // In progress: View order + Cancel order.
    expect(find.text('View order'), findsOneWidget);
    expect(find.text('Cancel order'), findsOneWidget);
    // Delivered: Buy again + Rate items.
    expect(find.text('Buy again'), findsOneWidget);
    expect(find.text('Rate items'), findsOneWidget);
    // A return open: its pill replaces the status and View return the actions.
    expect(find.text('RETURN IN PROGRESS'), findsOneWidget);
    expect(find.text('View return'), findsOneWidget);
    // One row per store: the statuses are the stores' own, in capitals.
    expect(find.text('OUT FOR DELIVERY'), findsOneWidget);
    expect(find.text('PROCESSING'), findsOneWidget);
    expect(find.text('DELIVERED'), findsOneWidget);

    // Returns keeps the order with a return.
    await tester.tap(find.text('Returns'));
    await tester.pumpAndSettle();
    expect(find.text('Order #HM-100150'), findsOneWidget);
    expect(find.text('Order #HM-100248'), findsNothing);

    // In progress drops the delivered ones.
    await tester.tap(find.text('In progress'));
    await tester.pumpAndSettle();
    expect(find.text('Order #HM-100248'), findsOneWidget);
    expect(find.text('Order #HM-100197'), findsNothing);
  });

  testWidgets('21 My orders: no Returns chip while returns are off', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      screen: const OrdersScreen(),
      account: FakeAccountRepository(orders: _orders('en')),
      hubApp: const HubAppState.unavailable(),
    );
    expect(find.text('Returns'), findsNothing);
    expect(find.text('View return'), findsNothing);
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('21 My orders: the loading skeleton', (tester) async {
    final key = GlobalKey();
    await pumpAudit(
      tester,
      boundary: key,
      screen: const OrdersScreen(),
      settle: false,
      overrides: [
        ordersControllerProvider.overrideWith(_LoadingOrders.new),
      ],
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await captureScreen(tester, key, 'audit_21_orders_loading_en');
    expect(tester.takeException(), isNull);
  });
}

/// An orders list that never finishes loading.
class _LoadingOrders extends OrdersController {
  @override
  OrdersState build() => const OrdersState();
}
