import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/audit_pump.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/marketplace_fakes.dart';

/// Renders Figma 22 "Order detail" (21:1376 / 52:2104) in English and Arabic to
/// build/test_screens/audit_22_order_detail_{en,ar}.png, and checks what the
/// frame draws from what the backend has: one card per store with its
/// timeline, the delivery address, the payment card and Cancel order.
Money _aed(double amount) => Money(amount: amount, currency: 'AED');

/// The order of the frame: loly store's dress is on its way (shipped by
/// Aramex), MIA CO is still preparing the sofa and the chair.
CustomerOrder _order(String locale, {bool cancel = true}) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  final lines = [
    OrderLine(
      name: ar
          ? 'فستان صدر طباعة الأزهار رباط مشدّ الخصر'
          : 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      price: _aed(50),
      sku: 'dress',
      seller: loly,
      uid: 'a',
      options: [ar ? 'مقاس: M' : 'Size: M'],
    ),
    OrderLine(
      name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
      quantity: 1,
      price: _aed(425),
      sku: 'sofa',
      seller: mia,
      uid: 'b',
      options: [ar ? 'اللون: تركوازي' : 'Colour: Teal'],
    ),
    OrderLine(
      name: ar
          ? 'كرسي طعام بارجل ذهبية معدنية'
          : 'Dining Chair with Gold Metal Legs',
      quantity: 2,
      price: _aed(34),
      sku: 'chair',
      seller: mia,
      uid: 'c',
      options: [ar ? 'اللون: أزرق فاتح' : 'Colour: Sky blue'],
    ),
  ];
  return CustomerOrder(
    number: 'HM-100248',
    status: ar ? 'قيد التنفيذ' : 'Processing',
    date: '2026-09-28 10:42:00',
    id: 'MjQ4',
    availableActions: cancel ? const {'CANCEL'} : const {},
    invoiceCount: 1,
    shipmentCount: 1,
    subtotal: _aed(543),
    shippingAmount: _aed(10),
    total: _aed(553),
    paymentMethodName: 'Visa •••• 4242',
    shippingName: ar ? 'سارة أحمد' : 'Sara Ahmed',
    shippingAddress: ar
        ? 'شقة 1204، مارينا غيت 2، دبي مارينا، دبي'
        : 'Apt 1204, Marina Gate 2, Dubai Marina, Dubai',
    lines: lines,
    packages: [
      OrderPackage(
        seller: loly,
        statusCode: 'processing',
        statusLabel: ar ? 'في الطريق إليك' : 'Out for delivery',
        state: 'processing',
        itemUids: const ['a'],
        shipments: [
          OrderPackageShipment(
            id: 's1',
            number: '000000031',
            createdAt: DateTime(2026, 9, 29, 9, 10),
            tracks: [
              OrderPackageTrack(
                carrierCode: 'aramex',
                carrierTitle: 'Aramex',
                number: '3345 1182',
                trackingUrl: Uri.parse(
                  'https://www.aramex.com/track/3345-1182',
                ),
              ),
            ],
          ),
        ],
      ),
      OrderPackage(
        seller: mia,
        statusCode: 'new',
        statusLabel: ar ? 'قيد التجهيز' : 'Processing',
        state: 'new',
        itemUids: const ['b', 'c'],
      ),
    ],
  );
}

/// The orders the frame does not draw, from the same lines.
List<(String, CustomerOrder)> _variants(String locale) {
  final base = _order(locale);
  final ar = locale == 'ar';
  final longName = ar
      ? 'كرسي طعام بارجل ذهبية معدنية وتنجيد مخملي فاخر بلون أزرق سماوي'
      : 'Dining Chair with Gold Metal Legs and Premium Velvet Upholstery in Sky Blue';
  // The server did not split it: one list, the order's own timeline and note.
  final unsplit = CustomerOrder(
    number: base.number,
    status: ar ? 'قيد التنفيذ' : 'Processing',
    date: base.date,
    id: base.id,
    availableActions: const {'CANCEL'},
    invoiceCount: 1,
    total: base.total,
    subtotal: base.subtotal,
    shippingAmount: base.shippingAmount,
    discount: _aed(25),
    discountLabel: ar ? 'خصم الإطلاق' : 'Launch offer',
    paymentMethodName: ar ? 'الدفع عند الاستلام' : 'Cash on delivery',
    shippingName: base.shippingName,
    shippingAddress: base.shippingAddress,
    billingName: ar ? 'أحمد' : 'Ahmed Hassan',
    billingAddress: ar
        ? 'مكتب 12، برج الخليج، دبي'
        : 'Office 12, Gulf Tower, Dubai',
    lines: [
      for (final l in base.lines)
        OrderLine(
          name: l.name,
          quantity: l.quantity,
          price: l.price,
          sku: l.sku,
          options: l.options,
        ),
    ],
    trackings: const [
      OrderTracking(title: 'Standard', number: '3345 1182', carrier: 'aramex'),
    ],
    comments: const [
      OrderComment(message: 'Packed', timestamp: '2026-09-28 16:05:00'),
      OrderComment(
        message: 'Handed to Aramex',
        timestamp: '2026-09-29 09:10:00',
      ),
    ],
    shipmentCount: 1,
  );
  CustomerOrder withStatus(
    String status,
    String state, {
    bool shipped = true,
  }) => CustomerOrder(
    number: base.number,
    status: status,
    date: base.date,
    id: base.id,
    availableActions: const {'REORDER'},
    invoiceCount: 1,
    shipmentCount: shipped ? 1 : 0,
    total: base.total,
    subtotal: base.subtotal,
    paymentMethodName: base.paymentMethodName,
    shippingName: base.shippingName,
    shippingAddress: base.shippingAddress,
    lines: base.lines,
    packages: [
      for (final p in base.packages)
        OrderPackage(
          seller: p.seller,
          statusCode: state,
          statusLabel: status,
          state: state,
          itemUids: p.itemUids,
          shipments: shipped ? p.shipments : const [],
        ),
    ],
  );
  final long = CustomerOrder(
    number: base.number,
    status: base.status,
    date: base.date,
    id: base.id,
    paymentMethodName: 'Visa •••• 4242 (Emirates NBD Platinum Credit)',
    shippingName: ar
        ? 'سارة أحمد عبد الرحمن المنصوري'
        : 'Sara Ahmed Abdulrahman Al Mansoori',
    shippingAddress: ar
        ? 'شقة 1204، برج مارينا غيت 2، شارع المارينا، دبي مارينا، دبي، الإمارات العربية المتحدة'
        : 'Apt 1204, Marina Gate Tower 2, Marina Walk Street, Dubai Marina, Dubai, United Arab Emirates',
    subtotal: _aed(12345.5),
    shippingAmount: _aed(10),
    total: _aed(12355.5),
    lines: [
      OrderLine(
        name: longName,
        quantity: 12,
        price: _aed(1028.8),
        options: [
          ar ? 'اللون: أزرق سماوي فاتح جدا' : 'Colour: Very light sky blue',
          ar ? 'المادة: مخمل' : 'Material: Velvet',
        ],
        seller: seller(
          'verylongstore',
          ar
              ? 'متجر الأثاث العصري الفاخر للمنزل'
              : 'The Modern Luxury Home Furniture Store',
        ),
        uid: 'x',
      ),
    ],
  );
  return [
    ('an order the server did not split', unsplit),
    ('a delivered order', withStatus(ar ? 'مكتمل' : 'Complete', 'complete')),
    (
      'a cancelled order',
      withStatus(ar ? 'ملغي' : 'Canceled', 'canceled', shipped: false),
    ),
    (
      'an order on hold',
      withStatus(ar ? 'معلق' : 'On Hold', 'holded', shipped: false),
    ),
    ('long names and amounts', long),
  ];
}

/// Both stores' phones: "Contact store" is drawn only for a store that has one.
List<Override> _phones() => [
  orderContactPhoneProvider(
    'loly',
  ).overrideWithValue(Uri.parse('tel:+971501234567')),
  orderContactPhoneProvider(
    'mia',
  ).overrideWithValue(Uri.parse('tel:+971507654321')),
  // Magento's stamps are read as the device's own, whatever zone the machine
  // running the capture is in.
  storeTimezoneProvider.overrideWith((ref) async => ''),
];

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('22 Order detail ($locale)', (tester) async {
      final key = GlobalKey();
      await pumpAudit(
        tester,
        locale: locale,
        boundary: key,
        height: locale == 'ar' ? 1600 : 1562,
        screen: OrderDetailScreen(order: _order(locale)),
        account: FakeAccountRepository(),
        overrides: _phones(),
      );
      await captureScreen(tester, key, 'audit_22_order_detail_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  // Orders that are not the frame's: the page must still lay out at phone
  // width (no overflow) in both languages — an order the server did not
  // split, a delivered one, a cancelled one, one on hold, long names.
  for (final locale in ['en', 'ar']) {
    final variants = _variants(locale);
    for (var i = 0; i < variants.length; i++) {
      final (name, order) = variants[i];
      testWidgets('22 Order detail: $name lays out ($locale)', (tester) async {
        final key = GlobalKey();
        await pumpAudit(
          tester,
          locale: locale,
          boundary: key,
          height: 1800,
          screen: OrderDetailScreen(order: order),
          overrides: _phones(),
        );
        await captureScreen(tester, key, 'audit_22_state${i}_$locale');
        expect(tester.takeException(), isNull);
        expect(find.byType(OrderDetailScreen), findsOneWidget);
      });
    }
  }

  testWidgets('22 Order detail: what the frame draws, from the backend', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      height: 1700,
      screen: OrderDetailScreen(order: _order('en')),
      overrides: _phones(),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text('Order #HM-100248'), findsOneWidget);
    expect(find.text('Placed 28 Sep 2026, 10:42'), findsOneWidget);
    // One card per store, each with the store's own status.
    expect(find.text('Package 1 · loly store'), findsOneWidget);
    expect(find.text('Package 2 · MIA CO'), findsOneWidget);
    expect(find.text('OUT FOR DELIVERY'), findsOneWidget);
    expect(find.text('PROCESSING'), findsOneWidget);
    // loly store's timeline ends at the carrier: confirmed, packed, shipped
    // (with its day and number), delivered ahead.
    expect(find.text(l10n.orderStepConfirmed), findsNWidgets(2));
    expect(find.text(l10n.orderStepPrepared), findsOneWidget);
    expect(find.textContaining('Aramex'), findsOneWidget);
    expect(find.textContaining('3345 1182'), findsOneWidget);
    // MIA CO is still being prepared: nothing shipped.
    expect(find.text(l10n.orderStepPreparing), findsOneWidget);
    // Items: the options chosen, the quantity, the line's total.
    expect(find.text('Size: M · Qty 1'), findsOneWidget);
    expect(find.text('Colour: Sky blue · Qty 2'), findsOneWidget);
    expect(find.text('AED 68'), findsOneWidget);
    // Track parcel only where a carrier page exists; Contact store for both.
    expect(find.text(l10n.orderTrackParcel), findsOneWidget);
    expect(find.text(l10n.orderContactStore), findsNWidgets(2));
    // Where it goes, what it cost, how it was paid.
    expect(find.text('Delivering to Sara Ahmed'), findsOneWidget);
    expect(
      find.text('Apt 1204, Marina Gate 2, Dubai Marina, Dubai'),
      findsOneWidget,
    );
    expect(find.text('Subtotal (4 items)'), findsOneWidget);
    expect(find.text('AED 543'), findsOneWidget);
    expect(find.text('AED 10'), findsOneWidget);
    expect(find.text('Paid with Visa •••• 4242'), findsOneWidget);
    expect(find.text('AED 553'), findsOneWidget);
    // Cancel order, naming both packages.
    expect(
      find.textContaining('Cancelling removes both packages'),
      findsOneWidget,
    );
    expect(find.text(l10n.orderCancelAction), findsOneWidget);
    // Not drawn: the backend has no documents, print or delivery estimate.
    expect(find.text('Documents'), findsNothing);
    expect(find.text('Download invoice'), findsNothing);
    expect(find.text('Print order'), findsNothing);
  });

  testWidgets('22 Order detail: Contact store only for a store with a phone', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      height: 1700,
      screen: OrderDetailScreen(order: _order('en')),
      overrides: [
        orderContactPhoneProvider(
          'mia',
        ).overrideWithValue(Uri.parse('tel:+971507654321')),
        storeTimezoneProvider.overrideWith((ref) async => ''),
      ],
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.orderContactStore), findsOneWidget);
  });

  testWidgets('22 Order detail: no Cancel order once a package shipped away', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      height: 1700,
      screen: OrderDetailScreen(order: _order('en', cancel: false)),
      overrides: _phones(),
      hubApp: const HubAppState.unavailable(),
    );
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.orderCancelAction), findsNothing);
  });
}
