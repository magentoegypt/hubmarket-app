import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/order_format.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_tracking_screen.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_deliveries.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_status_pill.dart';

import '../../support/fonts.dart';
import '../../support/order_fulfillment_fixtures.dart';
import '../../support/order_package_fixtures.dart';
import '../../support/order_screens_harness.dart';

/// "Delivery progress" (FulfillmentTracking `hm_fulfillment`, CL036-DEV17) on
/// the order detail (22) and Track order (26): the server's overall status and
/// its deliveries — seller, route, lines, courier and number, expected date,
/// timeline — in the store view's words, in place of what the screens infer from
/// invoices and shipments. There is no Figma frame for it: it is built from the
/// package card's vocabulary and the website's section.

/// The URIs "Track parcel" asked to open.
final List<Uri> _opened = <Uri>[];

Widget _app(
  CustomerOrder order, {
  String screen = AppRoutes.orderDetail,
  String locale = 'en',
  bool opens = true,
  ThemeMode themeMode = ThemeMode.light,
}) => orderScreensApp(
  order,
  screen: screen,
  locale: locale,
  opened: _opened,
  opens: opens,
  themeMode: themeMode,
);

/// Tall enough for the whole order: list items off screen are not built.
void _tallView(WidgetTester tester, {double width = 800}) {
  tester.view.physicalSize = Size(width, 4200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder _delivery(int n) => find.byKey(ValueKey('delivery-delivery-$n'));

Finder _in(Finder card, Finder finder) =>
    find.descendant(of: card, matching: finder);

/// The coloured 20 px discs of the timelines.
Finder _dots(Color color) => find.descendant(
  of: find.byType(OrderDeliveries),
  matching: find.byWidgetPredicate((widget) {
    if (widget is! Container) return false;
    final decoration = widget.decoration;
    return decoration is BoxDecoration &&
        decoration.shape == BoxShape.circle &&
        decoration.color == color &&
        widget.constraints?.maxWidth == 20;
  }),
);

String _day(DateTime utc, String locale) =>
    formatStamp(utc.toLocal(), 'd MMM yyyy', locale);

String _at(DateTime utc, String locale) => orderFmtStepAt(utc, locale);

/// HM-100248 with one delivery whose timeline is [steps].
CustomerOrder _timelineOrder(String status, List<String> steps) =>
    packagedOrder(
      fulfillment: OrderFulfillment(
        statusCode: status,
        statusLabel: statusLabelOf(status, 'en'),
        deliveries: [
          OrderDelivery(
            id: 'delivery-1',
            route: 'direct',
            routeLabel: routeLabelOf('direct', 'en'),
            statusCode: steps.last,
            statusLabel: statusLabelOf(steps.last, 'en'),
            itemUids: const [dressUid],
            timeline: [
              for (final step in steps)
                DeliveryStep(
                  statusCode: step,
                  statusLabel: statusLabelOf(step, 'en'),
                ),
            ],
          ),
        ],
      ),
    );

void main() {
  setUpAll(loadAppFonts);
  setUp(_opened.clear);

  group('22 order detail', () {
    testWidgets('the overall status, then each delivery with its details', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(_app(fulfilledOrder()));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDeliveries), findsOneWidget);
      expect(find.text('Delivery progress'), findsOneWidget);
      // The overall status (preparing: MIA CO's parcel is the slowest) beside
      // the title, and MIA CO's own pill under its delivery.
      expect(find.text('PREPARING'), findsNWidgets(2));
      expect(_delivery(1), findsOneWidget);
      expect(_delivery(2), findsOneWidget);

      // loly store: direct, on its way with DHL, a date set, three steps done.
      final first = _delivery(1);
      expect(_in(first, find.text('From the seller to you')), findsOneWidget);
      expect(
        _in(first, find.text('Sold by loly store · 1 item')),
        findsOneWidget,
      );
      expect(_in(first, find.text('ON THE WAY TO YOU')), findsOneWidget);
      expect(
        _in(first, find.text('Floral Print Corset-Waist Tie Dress')),
        findsOneWidget,
      );
      expect(_in(first, find.textContaining('DHL')), findsOneWidget);
      expect(_in(first, find.textContaining('1234567890')), findsOneWidget);
      expect(
        _in(
          first,
          find.text(
            'Expected delivery: ${_day(DateTime.utc(2026, 10, 15, 9), 'en')}',
          ),
        ),
        findsOneWidget,
      );
      expect(_in(first, find.text('Order placed')), findsOneWidget);
      expect(_in(first, find.text('Ready for courier pickup')), findsOneWidget);
      expect(_in(first, find.text('On the way to you')), findsOneWidget);
      expect(
        _in(first, find.text(_at(DateTime.utc(2026, 9, 28, 6, 42), 'en'))),
        findsOneWidget,
      );
      expect(
        _in(first, find.text(_at(DateTime.utc(2026, 9, 29, 6, 10), 'en'))),
        findsOneWidget,
      );
      expect(_in(first, find.text('Track parcel')), findsOneWidget);

      // MIA CO: still being prepared, nobody carries it yet, nothing to track.
      final second = _delivery(2);
      expect(
        _in(second, find.text('Sold by MIA CO · 2 items')),
        findsOneWidget,
      );
      expect(_in(second, find.text('PREPARING')), findsOneWidget);
      expect(_in(second, find.text('Corner Sofa Bed')), findsOneWidget);
      expect(
        _in(second, find.text('Dining Chair with Gold Metal Legs × 2')),
        findsOneWidget,
      );
      expect(_in(second, find.text('Order placed')), findsOneWidget);
      expect(_in(second, find.byIcon(HubIcons.truck)), findsNothing);
      expect(
        _in(second, find.textContaining('Expected delivery')),
        findsNothing,
      );
      expect(_in(second, find.text('Track parcel')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the store cards keep to the items: no second status', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(_app(fulfilledOrder()));
      await tester.pumpAndSettle();

      expect(find.byType(OrderPackageCard), findsNWidgets(2));
      expect(find.text('Package 1 · loly store'), findsOneWidget);
      expect(find.text('Package 2 · MIA CO'), findsOneWidget);
      // The stores' own pills and timelines are the deliveries' now.
      expect(find.text('PROCESSING'), findsNothing);
      expect(find.text('PENDING'), findsNothing);
      expect(find.text('Order confirmed'), findsNothing);
      expect(find.text('Packed by store'), findsNothing);
      expect(find.text('Being prepared by store'), findsNothing);
      // The only parcel to track is the delivery's.
      expect(find.text('Track parcel'), findsOneWidget);
      // What the store said and what it sells stay in the card.
      expect(find.text('Updates from the store'), findsOneWidget);
      expect(find.text('Packed and handed to DHL.'), findsOneWidget);
      expect(
        find.text('Floral Print Corset-Waist Tie Dress'),
        findsNWidgets(2),
      );
      expect(find.text('AED 50'), findsOneWidget);
    });

    testWidgets('a number no delivery lists stays under Tracking', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(_app(fulfilledOrder()));
      await tester.pumpAndSettle();

      // DHL's number is in loly store's delivery; the order's Aramex one is
      // in none of them (the delivery lists one courier), so it is not lost.
      expect(find.text('Tracking'), findsOneWidget);
      expect(find.text(aramexNumber), findsOneWidget);
      expect(find.textContaining(dhlNumber), findsOneWidget);
    });

    testWidgets('every number is in a delivery: no Tracking list', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          fulfilledOrder(
            trackings: const [
              OrderTracking(title: 'DHL', number: dhlNumber, carrier: 'dhl'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tracking'), findsNothing);
      // And the note that numbers come once it ships is the deliveries' job.
      expect(find.textContaining('Tracking details appear'), findsNothing);
      expect(find.textContaining(dhlNumber), findsOneWidget);
    });

    testWidgets('a number is the same with or without its spaces', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          fulfilledOrder(
            warehouse: true,
            trackings: const [
              OrderTracking(
                title: 'Aramex',
                number: '33451182',
                carrier: 'custom',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tracking'), findsNothing);
    });

    testWidgets('Track parcel opens the courier page', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(_app(fulfilledOrder()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track parcel'));
      await tester.pumpAndSettle();

      expect(_opened, [Uri.parse(dhlUrl)]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a page that will not open says so', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(_app(fulfilledOrder(), opens: false));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Track parcel'));
      await tester.pump();

      expect(_opened, hasLength(1));
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('the courier\'s number is copied', (tester) async {
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
      await tester.pumpWidget(
        _app(
          fulfilledOrder(
            trackings: const [
              OrderTracking(title: 'DHL', number: dhlNumber, carrier: 'dhl'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The package cards have no copy action of their own any more.
      expect(find.byTooltip('Copy tracking number'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy tracking number'));
      await tester.pump();

      expect(copied, [dhlNumber]);
      expect(find.text('Tracking number copied'), findsOneWidget);
    });

    testWidgets('through the warehouse: three legs, the last names no seller', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          fulfilledOrder(
            warehouse: true,
            trackings: const [
              OrderTracking(
                title: 'Aramex',
                number: aramexNumber,
                carrier: 'custom',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The overall status is the slowest leg into the warehouse: MIA's.
      expect(find.text('ON THE WAY TO OUR WAREHOUSE'), findsNWidgets(2));
      expect(find.text('From the seller to our warehouse'), findsNWidgets(2));
      expect(find.text('From our warehouse to you'), findsOneWidget);
      final out = _delivery(3);
      expect(_in(out, find.textContaining('Sold by')), findsNothing);
      expect(_in(out, find.text('3 items')), findsOneWidget);
      expect(_in(out, find.text('Hub Market delivery')), findsOneWidget);
      expect(
        _in(
          out,
          find.text(
            'Expected delivery: ${_day(DateTime.utc(2026, 10, 18, 9), 'en')}',
          ),
        ),
        findsOneWidget,
      );
      // loly store's leg: its own driver; MIA CO's: Aramex, a number to copy
      // and no page to open.
      expect(
        _in(_delivery(1), find.text("Seller's own delivery")),
        findsOneWidget,
      );
      expect(_in(_delivery(1), find.text('AT OUR WAREHOUSE')), findsOneWidget);
      expect(_in(_delivery(2), find.textContaining('Aramex')), findsOneWidget);
      expect(
        _in(_delivery(2), find.textContaining('3345 1182')),
        findsOneWidget,
      );
      expect(find.text('Track parcel'), findsNothing);
      expect(find.byTooltip('Copy tracking number'), findsOneWidget);
      // Without anything stored about the legs ahead, none is made up.
      expect(find.text('Delivered'), findsNothing);
    });

    testWidgets('without hm_fulfillment the stores keep their own status', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(_app(packagedOrder()));
      await tester.pumpAndSettle();

      expect(find.byType(OrderDeliveries), findsNothing);
      expect(find.text('Delivery progress'), findsNothing);
      expect(find.text('PROCESSING'), findsOneWidget);
      expect(find.text('PENDING'), findsOneWidget);
      expect(find.text('Packed by store'), findsOneWidget);
      expect(find.text('Track parcel'), findsOneWidget);
    });

    testWidgets('an order with nothing to deliver draws no section', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          packagedOrder(
            fulfillment: const OrderFulfillment(
              statusCode: 'ordered',
              statusLabel: 'Order placed',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivery progress'), findsNothing);
      expect(find.text('PROCESSING'), findsOneWidget);
      expect(find.text('Track parcel'), findsOneWidget);
    });

    testWidgets('Arabic: the server\'s words, a number kept left to right', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(_app(fulfilledOrder(locale: 'ar'), locale: 'ar'));
      await tester.pumpAndSettle();

      expect(find.text('حالة التوصيل'), findsOneWidget);
      expect(find.text('قيد التجهيز'), findsNWidgets(2));
      expect(find.text('من البائع إليك'), findsNWidgets(2));
      final first = _delivery(1);
      expect(
        _in(first, find.text('يبيعه متجر لولي · منتج واحد')),
        findsOneWidget,
      );
      // Its pill (no capitals in Arabic) and the step it stands on.
      expect(_in(first, find.text('في الطريق إليك')), findsNWidgets(2));
      expect(
        _in(
          first,
          find.text(
            'موعد التوصيل المتوقع: '
            '${_day(DateTime.utc(2026, 10, 15, 9), 'ar')}',
          ),
        ),
        findsOneWidget,
      );
      final lri = String.fromCharCode(0x2066);
      final pdi = String.fromCharCode(0x2069);
      expect(
        _in(first, find.textContaining('$lri$dhlTrackingNumber$pdi')),
        findsOneWidget,
      );
      expect(_in(first, find.text('تتبع الشحنة')), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(OrderDeliveries))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dark theme draws without errors', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(fulfilledOrder(), themeMode: ThemeMode.dark),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delivery progress'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('26 Track order', () {
    testWidgets('the banner is the server\'s status and the stages give way', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(fulfilledOrder(), screen: AppRoutes.orderTracking),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderTrackingScreen), findsOneWidget);
      // The status card: the server's words and the icon of its code.
      expect(find.text('Preparing'), findsOneWidget);
      expect(find.byIcon(HubIcons.package), findsOneWidget);
      // Not the stages inferred from invoices and shipments.
      expect(find.text('Order Status'), findsNothing);
      expect(find.text('Order Confirmed'), findsNothing);
      expect(find.text('Packed & Shipped'), findsNothing);
      // Delivery progress, without a second overall status beside its title:
      // the one pill is MIA CO's delivery.
      expect(find.text('Delivery progress'), findsOneWidget);
      expect(find.text('PREPARING'), findsOneWidget);
      expect(_delivery(1), findsOneWidget);
      expect(_delivery(2), findsOneWidget);
      expect(_in(_delivery(1), find.text('Track parcel')), findsOneWidget);
      expect(_in(_delivery(1), find.text('ON THE WAY TO YOU')), findsOneWidget);
    });

    testWidgets('the items keep their store cards, without a second status', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(fulfilledOrder(), screen: AppRoutes.orderTracking),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OrderPackageCard), findsNWidgets(2));
      expect(find.text('Package 1 · loly store'), findsOneWidget);
      expect(find.text('PROCESSING'), findsNothing);
      expect(find.text('Packed by store'), findsNothing);
      expect(find.text('Track parcel'), findsOneWidget);
    });

    testWidgets('the Tracking section only lists what no delivery shows', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(fulfilledOrder(), screen: AppRoutes.orderTracking),
      );
      await tester.pumpAndSettle();
      // The Aramex number is in no delivery.
      expect(find.text('Tracking'), findsOneWidget);
      expect(find.text(aramexNumber), findsOneWidget);

      await tester.pumpWidget(
        _app(
          fulfilledOrder(
            trackings: const [
              OrderTracking(title: 'DHL', number: dhlNumber, carrier: 'dhl'),
            ],
          ),
          screen: AppRoutes.orderTracking,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tracking'), findsNothing);
      expect(find.textContaining('Tracking details appear'), findsNothing);
    });

    testWidgets('a cancelled order reads cancelled, in red', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          packagedOrder(
            fulfillment: OrderFulfillment(
              statusCode: 'canceled',
              statusLabel: statusLabelOf('canceled', 'en'),
              deliveries: [
                OrderDelivery(
                  id: 'delivery-1',
                  route: 'direct',
                  routeLabel: routeLabelOf('direct', 'en'),
                  statusCode: 'canceled',
                  statusLabel: statusLabelOf('canceled', 'en'),
                  itemUids: const [dressUid],
                  timeline: [
                    DeliveryStep(
                      statusCode: 'ordered',
                      statusLabel: statusLabelOf('ordered', 'en'),
                    ),
                    DeliveryStep(
                      statusCode: 'canceled',
                      statusLabel: statusLabelOf('canceled', 'en'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          screen: AppRoutes.orderTracking,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Canceled'), findsNWidgets(2));
      expect(find.byIcon(HubIcons.circleX), findsOneWidget);
      expect(find.text('CANCELED'), findsOneWidget);
      expect(_dots(AppColors.danger), findsOneWidget);
    });

    testWidgets('without hm_fulfillment it is the stages, as before', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(packagedOrder(), screen: AppRoutes.orderTracking),
      );
      await tester.pumpAndSettle();

      expect(find.text('Order Status'), findsOneWidget);
      expect(find.text('Delivery progress'), findsNothing);
      expect(find.text('PROCESSING'), findsOneWidget);
    });

    testWidgets('Arabic mirrors it', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          fulfilledOrder(locale: 'ar'),
          screen: AppRoutes.orderTracking,
          locale: 'ar',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('حالة التوصيل'), findsOneWidget);
      // The banner, and MIA CO's pill (no capitals in Arabic): no overall
      // pill beside the title.
      expect(find.text('قيد التجهيز'), findsNWidgets(2));
      expect(find.text('من البائع إليك'), findsNWidgets(2));
      expect(
        Directionality.of(tester.element(find.byType(OrderDeliveries))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('on the test phone, 360 dp wide', () {
    for (final locale in ['en', 'ar']) {
      for (final screen in [AppRoutes.orderDetail, AppRoutes.orderTracking]) {
        testWidgets('the longest labels fit: $screen ($locale)', (
          tester,
        ) async {
          _tallView(tester, width: 360);
          await tester.pumpWidget(
            _app(
              fulfilledOrder(locale: locale, warehouse: true),
              screen: screen,
              locale: locale,
            ),
          );
          await tester.pumpAndSettle();

          expect(find.byType(OrderDeliveries), findsOneWidget);
          expect(_delivery(3), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('the timeline dots', () {
    testWidgets('a step behind is done, the one it stands on blue', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(_timelineOrder('on_the_way', ['ordered', 'on_the_way'])),
      );
      await tester.pumpAndSettle();

      expect(_dots(AppColors.successStrong), findsOneWidget);
      expect(_dots(AppColors.info), findsOneWidget);
      expect(_dots(AppColors.warning), findsNothing);
      expect(_dots(AppColors.danger), findsNothing);
    });

    testWidgets('a delay keeps its amber after the parcel moves on', (
      tester,
    ) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          _timelineOrder('on_the_way', ['ordered', 'delayed', 'on_the_way']),
        ),
      );
      await tester.pumpAndSettle();

      expect(_dots(AppColors.successStrong), findsOneWidget);
      expect(_dots(AppColors.warning), findsOneWidget);
      expect(_dots(AppColors.info), findsOneWidget);
    });

    testWidgets('arrived: every step is green', (tester) async {
      _tallView(tester);
      await tester.pumpWidget(
        _app(
          _timelineOrder('delivered', ['ordered', 'on_the_way', 'delivered']),
        ),
      );
      await tester.pumpAndSettle();

      expect(_dots(AppColors.successStrong), findsNWidgets(3));
      expect(_dots(AppColors.info), findsNothing);
    });
  });

  group('the status pill', () {
    final tones = {
      'delivered': (AppColors.successSubtle, AppColors.successStrong),
      'completed': (AppColors.successSubtle, AppColors.successStrong),
      'delayed': (AppColors.warningSubtle, AppColors.warning),
      'on_hold': (AppColors.warningSubtle, AppColors.warning),
      'canceled': (AppColors.dangerSurface, AppColors.danger),
      'refunded': (AppColors.dangerSurface, AppColors.danger),
      'on_the_way': (AppColors.infoSubtle, AppColors.info),
      'preparing': (AppColors.infoSubtle, AppColors.info),
      // A status this build does not know reads as moving, not as an error.
      'brand_new_status': (AppColors.infoSubtle, AppColors.info),
    };
    tones.forEach((code, colors) {
      testWidgets('$code wears its tone', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light('en'),
            home: Scaffold(
              body: DeliveryStatusPill(code: code, label: 'Label'),
            ),
          ),
        );

        final pill = tester.widget<StatusPill>(find.byType(StatusPill));
        expect(pill.background, colors.$1);
        expect(pill.foreground, colors.$2);
        expect(find.text('LABEL'), findsOneWidget);
      });
    });
  });

  test('every status has an icon, and an unknown one a moving truck', () {
    expect(deliveryIconOf('ordered'), HubIcons.shoppingBag);
    expect(deliveryIconOf('preparing'), HubIcons.package);
    expect(deliveryIconOf('ready_for_pickup'), HubIcons.package);
    expect(deliveryIconOf('to_hub'), HubIcons.truck);
    expect(deliveryIconOf('at_hub'), HubIcons.store);
    expect(deliveryIconOf('shipped'), HubIcons.truck);
    expect(deliveryIconOf('on_the_way'), HubIcons.truck);
    expect(deliveryIconOf('delivered'), HubIcons.circleCheck);
    expect(deliveryIconOf('completed'), HubIcons.circleCheck);
    expect(deliveryIconOf('delayed'), HubIcons.clock);
    expect(deliveryIconOf('on_hold'), HubIcons.circlePause);
    expect(deliveryIconOf('canceled'), HubIcons.circleX);
    expect(deliveryIconOf('refunded'), HubIcons.circleX);
    expect(deliveryIconOf('brand_new_status'), HubIcons.truck);
  });
}
