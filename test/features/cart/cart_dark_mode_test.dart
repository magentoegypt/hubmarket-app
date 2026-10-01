import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import 'cart_screen_harness.dart';

/// The cart is a light page of white cards (Figma 16), in dark mode too — as
/// checkout is — so its inks are the design's and never the dark theme's white,
/// which would vanish on the white cards.
void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('dark mode: the cart keeps the light frame\'s colours '
        '($locale)', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        cartScreenApp(
          locale: locale,
          cart: FilledCart(),
          dark: true,
          freeShipping: 150,
          boundary: key,
        ),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'cart_free_delivery_dark_$locale');

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      // A white track under the orange fill, on the pale orange card.
      expect(bar.backgroundColor, Colors.white);
      expect(bar.valueColor!.value, AppColors.accent);
      expect(bar.value, closeTo(100 / 150, 1e-9));
      final remaining = tester.widget<Text>(
        find.text(l10n.cartFreeShippingRemaining('AED 50')),
      );
      expect(remaining.style?.color, AppColors.accentStrong);
      // The summary's ink on its white card, not the dark theme's white.
      expect(
        tester.widget<Text>(find.text(l10n.checkoutTotalInclVat)).style?.color,
        AppColors.inkHeading,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('light mode draws the same colours', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      cartScreenApp(locale: 'en', cart: FilledCart(), freeShipping: 150),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.backgroundColor, Colors.white);
    expect(bar.valueColor!.value, AppColors.accent);
    expect(
      tester.widget<Text>(find.text('Total (incl. VAT)')).style?.color,
      AppColors.inkHeading,
    );
  });
}
