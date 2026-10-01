import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/orders_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../test/support/fakes.dart';
import '../../test/support/marketplace_fakes.dart';
import '../../test/support/returns_fakes.dart';
import 'audit_scene.dart';
import 'harness.dart';

/// Orders, returns, addresses and wishlist: E21 Orders, E21b Cancel order,
/// E22 Order detail, E23 Return request, E23b My returns, E23c Return detail,
/// E24 Addresses, E24b Address form, E25 Wishlist, E26 Track order.
///
/// E21 and E21b are the reference scenes (ported from
/// test/features/account/audit_orders_list_test.dart); the rest follow the
/// same pattern.
List<AuditScene> scenes() => [
  AuditScene(
    frame: 'E21_orders',
    name: 'default',
    screen: (_) => const OrdersScreen(),
    setup: (locale) => AuditSetup(
      account: FakeAccountRepository(orders: _orders(locale)),
      returns: FakeReturnsRepository(
        summaries: [_openReturn(seller('loly', 'loly store'))],
      ),
    ),
  ),
  // Figma 21b: "Cancel order" on the first card opens the sheet over the list.
  AuditScene(
    frame: 'E21b_cancel_order',
    name: 'default',
    screen: (_) => const OrdersScreen(),
    setup: (locale) => AuditSetup(
      account: FakeAccountRepository(orders: _orders(locale)),
      returns: FakeReturnsRepository(),
    ),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tester.tap(find.text(l10n.orderCancelAction));
      await pumpFor(tester, 500);
    },
  ),
];

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

OrderLine _line(String name, String uid, HmSellerSummary store) => OrderLine(
  name: name,
  quantity: 1,
  sku: 'SKU-$uid',
  seller: store,
  uid: uid,
);

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
        _package(mia, ar ? 'قيد التجهيز' : 'Processing', 'new', const [
          'b',
          'c',
        ]),
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
        _package(walmart, ar ? 'تم التوصيل' : 'Delivered', 'complete', const [
          'd',
          'e',
          'f',
        ]),
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
        _package(loly, ar ? 'تم التوصيل' : 'Delivered', 'complete', const [
          'g',
        ]),
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
