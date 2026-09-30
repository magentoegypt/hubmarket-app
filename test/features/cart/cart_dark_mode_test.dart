import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import 'cart_screen_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('dark mode: the free-delivery bar and totals follow the theme '
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
      // Was a white track glaring on the dark page.
      expect(bar.backgroundColor, Colors.white24);
      expect(bar.value, closeTo(100 / 150, 1e-9));
      final remaining = tester.widget<Text>(
        find.text(l10n.cartFreeDeliveryRemaining('AED 50.00')),
      );
      expect(remaining.style?.color, Colors.white);
      // The summary's ink and navy would vanish on the dark page.
      expect(
        tester.widget<Text>(find.text(l10n.cartTotal)).style?.color,
        Colors.white,
      );
      expect(
        tester.widget<Text>(find.text(l10n.cartOrderSummary)).style?.color,
        Colors.white,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('light mode keeps the Figma colours', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      cartScreenApp(locale: 'en', cart: FilledCart(), freeShipping: 150),
    );
    await tester.pumpAndSettle();

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.backgroundColor, Colors.white);
    expect(bar.valueColor!.value, AppColors.brandPrimary);
    expect(
      tester.widget<Text>(find.text('Total')).style?.color,
      AppColors.inkHeading,
    );
  });
}
