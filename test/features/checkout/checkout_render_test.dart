import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';

import 'checkout_harness.dart';

/// Renders each checkout step and Order placed, in English and Arabic, to
/// build/test_screens/ for comparison with Figma 17a / 17 / 18 / 18b / 19. The
/// assertions only guard against layout errors (overflow) and a wrong text
/// direction.
void main() {
  setUpAll(loadCheckoutFonts);

  Future<GlobalKey> mount(
    WidgetTester tester,
    String locale, {
    required double height,
    bool signedIn = false,
    String? registeredEmail,
  }) async {
    tester.view.physicalSize = Size(390, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      checkoutHarness(
        locale: locale,
        repository: checkoutRepository(registeredEmail: registeredEmail),
        signedIn: signedIn,
        boundary: key,
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
        height: 1080,
        registeredEmail: 'sara.ahmed@gmail.com',
      );
      await fillGuestAddress(tester);
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
      final key = await mount(tester, locale, height: 844, signedIn: true);
      await capture(tester, key, 'checkout_17_shipping_$locale');
      expect(find.text('Standard delivery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('18 payment ($locale)', (tester) async {
      final key = await mount(tester, locale, height: 844, signedIn: true);
      await tapText(tester, en ? 'Continue to payment' : 'المتابعة للدفع');
      await capture(tester, key, 'checkout_18_payment_$locale');
      expect(find.text('Cash on delivery'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('18b review ($locale)', (tester) async {
      final key = await mount(tester, locale, height: 1120, signedIn: true);
      await tapText(tester, en ? 'Continue to payment' : 'المتابعة للدفع');
      await tapText(tester, en ? 'Review order' : 'مراجعة الطلب');
      await capture(tester, key, 'checkout_18b_review_$locale');
      expect(find.text('Corner Sofa Bed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('19 order placed ($locale)', (tester) async {
      final key = await mount(tester, locale, height: 844, signedIn: true);
      await tapText(tester, en ? 'Continue to payment' : 'المتابعة للدفع');
      await tapText(tester, en ? 'Review order' : 'مراجعة الطلب');
      await tester.tap(find.byIcon(Icons.lock_outline));
      await tester.pumpAndSettle();
      await capture(tester, key, 'checkout_19_order_placed_$locale');
      expectDirection(tester, OrderSuccessScreen, locale);
      expect(tester.takeException(), isNull);
    });
  }
}
