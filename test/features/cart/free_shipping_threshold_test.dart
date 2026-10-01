import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import '../checkout/checkout_harness.dart';
import 'cart_screen_harness.dart';

/// The storefront's free-shipping threshold (`hmAppConfig.shipping.free_over`,
/// the figure its mini-cart counts down to) lights up the cart's free-delivery
/// bar (16) and checkout's "Free shipping on orders over …" (17) in Build 2.
const HmAppConfig _withThreshold = HmAppConfig(
  storeCode: 'en',
  locale: 'en_US',
  search: HmSearchConfig(hint: 'Search 20,000+ products'),
  features: {'returns': true, 'store_credit': false},
  shipping: HmShippingConfig(freeOver: 150, currency: 'AED'),
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('cart: the bar counts down to the store threshold ($locale)', (
      tester,
    ) async {
      phoneView(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        cartScreenApp(
          locale: locale,
          cart: FilledCart(),
          hubApp: _withThreshold,
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'cart_free_delivery_$locale');

      // AED 100 in the cart, free over AED 150.
      expect(
        find.text(l10n.cartFreeDeliveryRemaining('AED 50')),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(100 / 150, 1e-9));
      expect(tester.takeException(), isNull);
    });

    testWidgets('checkout: the shipping step names the threshold ($locale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        checkoutHarness(
          locale: locale,
          repository: checkoutRepository(),
          signedIn: true,
          boundary: key,
          hubApp: hubAppOverride(const HubAppState.available(_withThreshold)),
        ),
      );
      await tester.pumpAndSettle();
      await capture(tester, key, 'checkout_17_free_shipping_$locale');

      expect(
        find.text(l10n.checkoutFreeShippingOver('AED 150')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a store without a threshold: no bar', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      cartScreenApp(
        locale: 'en',
        cart: FilledCart(),
        hubApp: const HmAppConfig(storeCode: 'en'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('Build 1: no bar', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(cartScreenApp(locale: 'en', cart: FilledCart()));
    await tester.pumpAndSettle();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
