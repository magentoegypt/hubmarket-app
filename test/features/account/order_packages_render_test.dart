import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';

import '../../support/fonts.dart';
import '../../support/order_package_fixtures.dart';
import '../../support/order_screens_harness.dart';
import '../checkout/checkout_harness.dart' as checkout;

/// Renders 22 order detail and 26 Track order with per-store packages
/// (HubAppOrders `hm_packages`) in English and Arabic to build/test_screens/
/// for comparison with Figma 22 (21:1376) and 26 (85:3365). Assertions only
/// guard against layout errors and a wrong text direction.
void main() {
  setUpAll(loadAppFonts);

  Future<void> render(
    WidgetTester tester,
    Widget Function(GlobalKey key) app,
    String name, {
    required double height,
    required String locale,
  }) async {
    tester.view.physicalSize = Size(390, height);
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
      Directionality.of(tester.element(find.byType(OrderPackageCard).first)),
      locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    );
  }

  for (final locale in ['en', 'ar']) {
    testWidgets('22 order detail by package ($locale)', (tester) async {
      await render(
        tester,
        (key) => orderScreensApp(
          packagedOrder(locale: locale),
          locale: locale,
          boundary: key,
        ),
        'p31_22_packages_$locale',
        height: 1400,
        locale: locale,
      );
      expect(find.byType(OrderPackageCard), findsNWidgets(2));
    });

    testWidgets('26 track order by package ($locale)', (tester) async {
      await render(
        tester,
        (key) => orderScreensApp(
          packagedOrder(locale: locale, placedAsGuest: true),
          screen: AppRoutes.orderTracking,
          locale: locale,
          boundary: key,
        ),
        'p31_26_packages_$locale',
        height: 1450,
        locale: locale,
      );
      expect(find.byType(OrderPackageCard), findsNWidgets(2));
    });
  }

  testWidgets('22 order detail by package (en, dark)', (tester) async {
    await render(
      tester,
      (key) => orderScreensApp(
        packagedOrder(),
        themeMode: ThemeMode.dark,
        boundary: key,
      ),
      'p31_22_packages_en_dark',
      height: 1400,
      locale: 'en',
    );
  });
}
