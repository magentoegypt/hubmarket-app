import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_tracking_screen.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';

import '../../support/order_package_fixtures.dart';
import '../../support/order_screens_harness.dart';

/// Figma 22 order detail and 26 Track order with the server's packages: each
/// store's status and timeline, its shipments with "Track parcel" or the number
/// to copy, what the store said, and its items. The order's totals are the
/// Payment card's (the frame has no per-store totals).

/// The URIs "Track parcel" asked to open.
final List<Uri> _opened = <Uri>[];

Widget _app(
  CustomerOrder order, {
  String screen = AppRoutes.orderDetail,
  String locale = 'en',
  bool opens = true,
}) => orderScreensApp(
  order,
  screen: screen,
  locale: locale,
  opened: _opened,
  opens: opens,
);

/// Tall enough for the whole order: list items off screen are not built.
void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _inCard(int index, Finder finder) => find.descendant(
  of: find.byType(OrderPackageCard).at(index),
  matching: finder,
);

void main() {
  setUp(_opened.clear);

  testWidgets('22: each package has its status, timeline and shipments', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(_app(packagedOrder()));
    await tester.pumpAndSettle();

    expect(find.byType(OrderPackageCard), findsNWidgets(2));
    expect(find.text('Package 1 · loly store'), findsOneWidget);
    expect(find.text('Package 2 · MIA CO'), findsOneWidget);
    // The store's own status, one pill per package.
    expect(_inCard(0, find.text('PROCESSING')), findsOneWidget);
    expect(_inCard(1, find.text('PENDING')), findsOneWidget);

    // loly store shipped: confirmed, packed and shipped are behind it, with
    // both numbers under Shipped and one page to open.
    expect(_inCard(0, find.text('Order confirmed')), findsOneWidget);
    expect(_inCard(0, find.text('Packed by store')), findsOneWidget);
    expect(_inCard(0, find.text('Shipped')), findsOneWidget);
    expect(_inCard(0, find.text('Delivered')), findsOneWidget);
    expect(_inCard(0, find.textContaining('· DHL')), findsOneWidget);
    expect(_inCard(0, find.textContaining(dhlNumber)), findsOneWidget);
    expect(_inCard(0, find.textContaining('Aramex')), findsOneWidget);
    expect(_inCard(0, find.textContaining(aramexNumber)), findsOneWidget);
    expect(find.text('Track parcel'), findsOneWidget);
    // The DHL number is on its page; the typed Aramex one is copied.
    expect(find.byTooltip('Copy tracking number'), findsOneWidget);
    expect(_inCard(0, find.text('Updates from the store')), findsOneWidget);
    expect(_inCard(0, find.text('Packed and handed to DHL.')), findsOneWidget);
    // The dress, its options-free caption and the line's total.
    expect(_inCard(0, find.text('Qty 1')), findsOneWidget);
    expect(_inCard(0, find.text('AED 50')), findsOneWidget);

    // MIA CO: still being prepared, nothing shipped, nothing to track.
    expect(_inCard(1, find.text('Being prepared by store')), findsOneWidget);
    expect(_inCard(1, find.text('Shipped')), findsOneWidget);
    expect(_inCard(1, find.textContaining('DHL')), findsNothing);
    // The chair is two at 34.
    expect(_inCard(1, find.text('AED 68')), findsOneWidget);

    // Every number is in a card: no order-level Tracking list repeats them.
    expect(find.text('Tracking'), findsNothing);
    expect(find.textContaining(dhlNumber), findsOneWidget);
  });

  testWidgets('22: the Payment card is the order\'s, not each store\'s', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(_app(packagedOrder()));
    await tester.pumpAndSettle();

    expect(find.text('Payment'), findsOneWidget);
    expect(find.text('Subtotal (4 items)'), findsOneWidget);
    expect(find.text('AED 543'), findsOneWidget);
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('−AED 25'), findsOneWidget);
    expect(find.text('Delivery'), findsOneWidget);
    expect(find.text('AED 10'), findsOneWidget);
    // Not invoiced yet (no invoice on the order): the method's own name.
    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(find.text('AED 528'), findsOneWidget);
    // The stores' own totals have no place in the frame.
    expect(find.text('Package total'), findsNothing);
  });

  testWidgets('Track parcel opens the carrier page', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(packagedOrder()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Track parcel'));
    await tester.pumpAndSettle();

    expect(_opened, [Uri.parse(dhlUrl)]);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a page that will not open says so', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(_app(packagedOrder(), opens: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Track parcel'));
    await tester.pump();

    expect(_opened, hasLength(1));
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a number without a page is copied', (tester) async {
    _tallView(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(_app(packagedOrder()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Copy tracking number'));
    await tester.pump();

    expect(copied, [aramexNumber]);
    expect(find.text('Tracking number copied'), findsOneWidget);
  });

  testWidgets('a number no package shows stays in the order Tracking list', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(
      _app(
        packagedOrder(
          trackings: const [
            OrderTracking(title: 'DHL', number: dhlNumber, carrier: 'dhl'),
            OrderTracking(title: 'UPS', number: '1Z999', carrier: 'ups'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tracking'), findsOneWidget);
    expect(find.text('1Z999'), findsOneWidget);
    // Shown in its card only.
    expect(find.textContaining(dhlNumber), findsOneWidget);
  });

  testWidgets('before any shipment each timeline says it is being prepared', (
    tester,
  ) async {
    _tallView(tester);
    final order = packagedOrder(trackings: const []);
    final unshipped = CustomerOrder(
      number: order.number,
      status: order.status,
      date: order.date,
      lines: order.lines,
      packages: [
        for (final p in order.packages)
          OrderPackage(
            seller: p.seller,
            statusCode: p.statusCode,
            statusLabel: p.statusLabel,
            state: p.state,
            itemUids: p.itemUids,
            subtotal: p.subtotal,
            grandTotal: p.grandTotal,
          ),
      ],
    );
    await tester.pumpWidget(_app(unshipped));
    await tester.pumpAndSettle();

    // Nothing is shipped: no Tracking card, no parcel, both stores preparing.
    expect(find.text('Tracking'), findsNothing);
    expect(find.text('Track parcel'), findsNothing);
    expect(find.text('Being prepared by store'), findsNWidgets(2));
    expect(find.text('Packed by store'), findsNothing);
  });

  testWidgets('without packages the cards are the sellers\', as before', (
    tester,
  ) async {
    _tallView(tester);
    final order = packagedOrder();
    await tester.pumpWidget(
      _app(
        CustomerOrder(
          number: order.number,
          status: order.status,
          date: order.date,
          lines: order.lines,
          trackings: order.trackings,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Package 1 · loly store'), findsOneWidget);
    // No store status without the server's split, and no timeline to draw.
    expect(find.text('PROCESSING'), findsNothing);
    expect(find.text('Order confirmed'), findsNothing);
    expect(find.text('Track parcel'), findsNothing);
    // The numbers are in the order's Tracking list, as today.
    expect(find.text('Tracking'), findsOneWidget);
    expect(find.text(dhlNumber), findsOneWidget);
  });

  testWidgets('26: Track order shows the same package cards', (tester) async {
    _tallView(tester);
    await tester.pumpWidget(
      _app(packagedOrder(placedAsGuest: true), screen: AppRoutes.orderTracking),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OrderTrackingScreen), findsOneWidget);
    expect(find.text('Package 1 · loly store'), findsOneWidget);
    expect(_inCard(0, find.text('PROCESSING')), findsOneWidget);
    expect(_inCard(1, find.text('PENDING')), findsOneWidget);
    expect(_inCard(1, find.text('Being prepared by store')), findsOneWidget);
    expect(find.text('Track parcel'), findsOneWidget);
    // The numbers are in the cards; the Tracking list doesn't repeat them.
    expect(find.textContaining(dhlNumber), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Arabic: the store\'s labels, numbers kept left to right', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(_app(packagedOrder(locale: 'ar'), locale: 'ar'));
    await tester.pumpAndSettle();

    expect(find.text('الطرد 1 · متجر لولي'), findsOneWidget);
    expect(_inCard(0, find.text('قيد التنفيذ')), findsOneWidget);
    expect(_inCard(0, find.text('جهّزه المتجر')), findsOneWidget);
    expect(find.text('تتبع الشحنة'), findsOneWidget);
    // The number sits in a left-to-right isolate inside the Arabic line.
    final lri = String.fromCharCode(0x2066);
    final pdi = String.fromCharCode(0x2069);
    expect(
      _inCard(0, find.textContaining('$lri$dhlNumber$pdi')),
      findsOneWidget,
    );
    expect(
      Directionality.of(tester.element(find.byType(OrderPackageCard).first)),
      TextDirection.rtl,
    );
  });
}
