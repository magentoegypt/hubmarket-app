import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_tracking_screen.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import '../../support/order_package_fixtures.dart';
import '../../support/order_screens_harness.dart';

/// Figma 22 order detail and 26 Track order with the server's packages: each
/// store's status, shipments with "Track parcel" or the number to copy, what
/// the store said, and the package's totals.

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

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

void main() {
  setUp(_opened.clear);

  testWidgets('22: each package has its status, shipments and totals', (
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

    // loly store shipped: the shipment, both numbers, one page to open.
    expect(_inCard(0, find.text('Shipment #000000031')), findsOneWidget);
    expect(_inCard(0, find.text('DHL')), findsOneWidget);
    expect(_inCard(0, find.text(dhlNumber)), findsOneWidget);
    expect(_inCard(0, find.text('Aramex')), findsOneWidget);
    expect(_inCard(0, find.text(aramexNumber)), findsOneWidget);
    expect(find.text('Track parcel'), findsOneWidget);
    expect(find.byTooltip('Copy tracking number'), findsNWidgets(2));
    expect(_inCard(0, find.text('Updates from the store')), findsOneWidget);
    expect(_inCard(0, find.text('Packed and handed to DHL.')), findsOneWidget);
    expect(_inCard(0, find.text('Package total')), findsOneWidget);
    // The dress's price, the package subtotal and the package total.
    expect(_inCard(0, find.text('AED 50')), findsNWidgets(3));

    // MIA CO: nothing shipped yet, a discount, no delivery of its own.
    expect(_inCard(1, find.textContaining('Shipment')), findsNothing);
    expect(_inCard(1, find.text('Discount')), findsOneWidget);
    expect(_inCard(1, find.text('−AED 25')), findsOneWidget);
    expect(_inCard(1, find.text('AED 468')), findsOneWidget);
    expect(_inCard(1, find.text('Shipping')), findsNothing);

    // Every number is in a card: no order-level Tracking list repeats them.
    expect(find.text('Tracking'), findsNothing);
    expect(find.text(dhlNumber), findsOneWidget);
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

    await tester.tap(find.byTooltip('Copy tracking number').last);
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
    expect(find.text(dhlNumber), findsOneWidget);
  });

  testWidgets('a store that charged its own delivery shows it', (
    tester,
  ) async {
    _tallView(tester);
    await tester.pumpWidget(_app(packagedOrder(lolyDelivery: _aed(10))));
    await tester.pumpAndSettle();

    expect(_inCard(0, find.text('Vendor Table Rate')), findsOneWidget);
    expect(_inCard(0, find.text('Shipping')), findsOneWidget);
    expect(_inCard(0, find.text('AED 10')), findsOneWidget);
    expect(_inCard(0, find.text('AED 60')), findsOneWidget);
    expect(_inCard(1, find.text('Shipping')), findsNothing);
  });

  testWidgets('before any shipment the order Tracking note stays', (
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

    expect(find.text('Tracking'), findsOneWidget);
    expect(
      find.text('Tracking details appear here once your order ships.'),
      findsOneWidget,
    );
    expect(find.text('Track parcel'), findsNothing);
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
    expect(find.text('PROCESSING'), findsNothing);
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
    expect(find.text('Track parcel'), findsOneWidget);
    expect(_inCard(1, find.text('AED 468')), findsOneWidget);
    // The numbers are in the cards; the Tracking list doesn't repeat them.
    expect(find.text(dhlNumber), findsOneWidget);
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
    expect(find.text('تتبّع الطرد'), findsOneWidget);
    expect(find.text('إجمالي الطرد'), findsNWidgets(2));
    final number = tester.widget<Text>(_inCard(0, find.text(dhlNumber)));
    expect(number.textDirection, TextDirection.ltr);
    expect(
      Directionality.of(tester.element(find.byType(OrderPackageCard).first)),
      TextDirection.rtl,
    );
  });
}
