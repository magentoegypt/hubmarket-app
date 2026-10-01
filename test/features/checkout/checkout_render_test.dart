import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';

import '../../support/store_credit_fakes.dart';
import 'checkout_harness.dart';

/// Renders each checkout step and Order placed, in English and Arabic, to
/// build/test_screens/ for comparison with Figma 17a / 17 / 18 / 18b / 19. The
/// frames show the order as HubApp serves it — lines grouped by store, the
/// store's free-shipping threshold (AED 600), AED 120 of store credit to use —
/// so the renders do too. The assertions only guard against layout errors
/// (overflow) and a wrong text direction.
void main() {
  setUpAll(loadCheckoutFonts);

  Future<GlobalKey> mount(
    WidgetTester tester,
    String locale, {
    required double height,
    bool signedIn = false,
    bool darkMode = false,
    String? registeredEmail,
    bool hubApp = false,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    final CartRepository? cart = hubApp
        ? SellerCheckoutCartRepository(locale)
        : null;
    await tester.pumpWidget(
      checkoutHarness(
        locale: locale,
        repository: checkoutRepository(registeredEmail: registeredEmail),
        signedIn: signedIn,
        darkMode: darkMode,
        boundary: key,
        cartRepository: cart,
        // Figma 18: "Use my credit — AED 120.00 available".
        hubApp: hubApp
            ? accountHubApp(deployed: true, storeCredit: true)
            : null,
        overrides: hubApp
            ? [
                freeShippingThresholdProvider.overrideWith((ref) async => 600),
                storeCreditRepositoryProvider.overrideWithValue(
                  FakeStoreCreditRepository(cartCredit: sampleCartCredit()),
                ),
              ]
            : const [],
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  void expectDirection(WidgetTester tester, Type screen, String locale) {
    expect(
      Directionality.of(tester.element(find.byType(screen))),
      locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    );
  }

  for (final locale in ['en', 'ar']) {
    final en = locale == 'en';

    testWidgets('17a guest contact + address ($locale)', (tester) async {
      final key = await mount(
        tester,
        locale,
        height: 1101,
        registeredEmail: 'sara.ahmed@gmail.com',
      );
      await fillGuestAddress(tester);
      // No field keeps the focus ring the last tap left it (the frame draws the
      // email focused as a state sample; the layout is what is compared).
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture(tester, key, 'checkout_17a_guest_$locale');
      expect(
        find.text(
          en
              ? 'You already have an account with us.'
              : 'لديك حساب لدينا بالفعل.',
        ),
        findsOneWidget,
      );
      expectDirection(tester, CheckoutScreen, locale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('17 ship to + shipping method ($locale)', (tester) async {
      final key = await mount(
        tester,
        locale,
        height: 844,
        signedIn: true,
        hubApp: true,
      );
      await capture(tester, key, 'checkout_17_shipping_$locale');
      expect(find.text('Standard delivery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('18 payment ($locale)', (tester) async {
      final key = await mount(
        tester,
        locale,
        height: 1048,
        signedIn: true,
        hubApp: true,
      );
      await tapText(tester, en ? 'Continue to payment' : 'المتابعة للدفع');
      await capture(tester, key, 'checkout_18_payment_$locale');
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('18b review ($locale)', (tester) async {
      final key = await mount(
        tester,
        locale,
        height: 1147,
        signedIn: true,
        hubApp: true,
      );
      await tapText(tester, en ? 'Continue to payment' : 'المتابعة للدفع');
      await tapText(tester, en ? 'Review order' : 'مراجعة الطلب');
      await capture(tester, key, 'checkout_18b_review_$locale');
      expect(
        find.text(en ? 'Corner Sofa Bed' : 'كنبة سرير ركنه'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('19 order placed ($locale)', (tester) async {
      final key = await mount(
        tester,
        locale,
        height: 844,
        signedIn: true,
        hubApp: true,
      );
      await tapText(tester, en ? 'Continue to payment' : 'المتابعة للدفع');
      await tapText(tester, en ? 'Review order' : 'مراجعة الطلب');
      await tester.tap(find.byIcon(HubIcons.lock));
      await tester.pumpAndSettle();
      await capture(tester, key, 'checkout_19_order_placed_$locale');
      expectDirection(tester, OrderSuccessScreen, locale);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('checkout stays light in dark mode, so the form is legible', (
    tester,
  ) async {
    final key = await mount(tester, 'en', height: 1101, darkMode: true);
    await fillGuestAddress(tester);
    await capture(tester, key, 'checkout_17a_guest_dark');
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byType(TextField).first,
        matching: find.byType(EditableText),
      ),
    );
    // Ink on the white card, not the dark theme's white.
    expect(field.style.color, isNot(Colors.white));
    expect(tester.takeException(), isNull);
  });
}
