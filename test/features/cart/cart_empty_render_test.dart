import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import 'cart_screen_harness.dart';

/// Figma S1 "Empty cart": a plain "My cart" header, the pale disc, the invitation
/// and the two ways on — rendered in both languages for comparison with the
/// frames (`audit_S1_empty_cart`).
void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('audit_S1_empty_cart ($locale)', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        cartScreenApp(
          locale: locale,
          cart: FakeCartRepository(),
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'audit_S1_empty_cart_$locale');

      expect(find.text(l10n.cartHeading), findsOneWidget);
      expect(find.text(l10n.cartEmptyTitle), findsOneWidget);
      expect(find.text(l10n.cartEmptyBody), findsOneWidget);
      expect(find.text(l10n.cartStartShopping), findsOneWidget);
      expect(find.text(l10n.cartEmptyWishlist), findsOneWidget);
      // No selection mode, no count, no checkout bar with nothing in the cart.
      expect(find.text(l10n.cartSelect), findsNothing);
      expect(find.text(l10n.cartCheckout), findsNothing);
      expect(
        Directionality.of(tester.element(find.text(l10n.cartEmptyTitle))),
        locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Start shopping goes Home, View wishlist to the wishlist', (
    tester,
  ) async {
    phoneView(tester);
    await tester.pumpWidget(
      cartScreenApp(locale: 'en', cart: FakeCartRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('View wishlist'));
    await tester.pumpAndSettle();
    expect(find.text(AppRoutes.wishlist), findsOneWidget);
  });

  testWidgets('Start shopping goes Home', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      cartScreenApp(locale: 'en', cart: FakeCartRepository()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start shopping'));
    await tester.pumpAndSettle();
    expect(find.text(AppRoutes.home), findsOneWidget);
  });
}
