import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_deliveries.dart';

import '../../support/fonts.dart';
import '../../support/order_fulfillment_fixtures.dart';
import '../../support/order_screens_harness.dart';
import '../checkout/checkout_harness.dart' as checkout;

/// Renders 22 order detail and 26 Track order with the server's delivery
/// progress (FulfillmentTracking `hm_fulfillment`) in English and Arabic, as an
/// order placed before fulfillment planning and as one routed through the
/// warehouse, to build/test_screens/ for review at the test phone's 360 dp.
/// There is no Figma frame for it. Assertions only guard against layout errors
/// and a wrong text direction.
void main() {
  setUpAll(loadAppFonts);

  Future<void> render(
    WidgetTester tester,
    Widget Function(GlobalKey key) app,
    String name, {
    required double height,
    required String locale,
  }) async {
    tester.view.physicalSize = Size(360, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await withRealShadows(() async {
      await tester.pumpWidget(app(key));
      await tester.pumpAndSettle();
      await checkout.capture(tester, key, name);
    });
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(OrderDeliveries))),
      locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    );
  }

  for (final locale in ['en', 'ar']) {
    for (final warehouse in [false, true]) {
      final route = warehouse ? 'warehouse' : 'direct';
      testWidgets('22 order detail, deliveries $route ($locale)', (
        tester,
      ) async {
        await render(
          tester,
          (key) => orderScreensApp(
            fulfilledOrder(locale: locale, warehouse: warehouse),
            locale: locale,
            boundary: key,
          ),
          'dev17_22_deliveries_${route}_$locale',
          height: warehouse ? 2300 : 1900,
          locale: locale,
        );
      });

      testWidgets('26 track order, deliveries $route ($locale)', (
        tester,
      ) async {
        await render(
          tester,
          (key) => orderScreensApp(
            fulfilledOrder(locale: locale, warehouse: warehouse),
            screen: AppRoutes.orderTracking,
            locale: locale,
            boundary: key,
          ),
          'dev17_26_deliveries_${route}_$locale',
          height: warehouse ? 2600 : 2200,
          locale: locale,
        );
      });
    }
  }
}
