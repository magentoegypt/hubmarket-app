import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/widgets/empty_state.dart';
import 'package:hubmarket_app/core/widgets/hub_button.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

/// The state page the S frames share. Laid out as Figma S1 ("Your cart is
/// empty": the area between the 56 px app bar and the 84 px tab bar) so the
/// capture lines up with that frame.
Widget _app(Widget state, {String locale = 'en', GlobalKey? boundary}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.only(top: 103, bottom: 84),
        child: state,
      ),
    ),
  );
  return boundary == null ? app : RepaintBoundary(key: boundary, child: app);
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _emptyCart() => EmptyState(
  icon: HubIcons.shoppingCart,
  title: 'Your cart is empty',
  body: 'Browse hundreds of local stores and add something you love.',
  action: HubButton(label: 'Start shopping', onPressed: () {}),
  secondaryAction: HubButton(
    label: 'View wishlist',
    style: HubButtonStyle.ghost,
    onPressed: () {},
  ),
);

void main() {
  setUpAll(loadAppFonts);

  testWidgets('S1: the disc, the heading, the body and two actions', (
    tester,
  ) async {
    _phone(tester);
    final key = GlobalKey();
    await tester.pumpWidget(_app(_emptyCart(), boundary: key));
    await tester.pumpAndSettle();
    await captureScreen(tester, key, 'empty_state_s1_en');

    // Figma S1: the disc 112 at y = 103 + 156.5, the title 14 under it, the
    // body 14 under that, the buttons 8 + 14 lower and 10 apart, 326 wide.
    final disc = tester.getRect(
      find.ancestor(
        of: find.byIcon(HubIcons.shoppingCart),
        matching: find.byType(Container),
      ),
    );
    expect(disc.size, const Size(112, 112));
    expect(disc.top, closeTo(103 + 156.5, 0.6));
    final title = tester.getRect(find.text('Your cart is empty'));
    expect(title.top - disc.bottom, closeTo(14, 0.6));
    final buttons = find.byType(HubButton);
    final first = tester.getRect(buttons.at(0));
    final second = tester.getRect(buttons.at(1));
    expect(first.width, 326);
    expect(first.height, 52);
    expect(second.top - first.bottom, 10);
    expect(first.top, closeTo(103 + 378.5 + 8, 0.6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the default tone is S1\'s orange; other frames set their own', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(_emptyCart()));
    await tester.pumpAndSettle();
    var glyph = tester.widget<Icon>(find.byIcon(HubIcons.shoppingCart));
    expect(glyph.color, AppColors.accentStrong);
    expect(glyph.size, 48);
    var disc = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(HubIcons.shoppingCart),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((disc.decoration! as BoxDecoration).color, AppColors.accentSubtle);

    // S2 "No results": a grey disc with a muted glyph.
    await tester.pumpWidget(
      _app(
        const EmptyState(
          icon: HubIcons.search,
          title: 'No results',
          discColor: AppColors.surfaceSubtle,
          iconColor: AppColors.inkMuted,
        ),
      ),
    );
    await tester.pumpAndSettle();
    glyph = tester.widget<Icon>(find.byIcon(HubIcons.search));
    expect(glyph.color, AppColors.inkMuted);
    disc = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(HubIcons.search),
            matching: find.byType(Container),
          )
          .first,
    );
    expect((disc.decoration! as BoxDecoration).color, AppColors.surfaceSubtle);
  });

  testWidgets('without a body or actions it is the disc and the title', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(const EmptyState(icon: HubIcons.store, title: 'Nothing here')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byType(HubButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('it mirrors in Arabic and stays centred', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(_emptyCart(), locale: 'ar'));
    await tester.pumpAndSettle();
    final disc = tester.getRect(
      find.ancestor(
        of: find.byIcon(HubIcons.shoppingCart),
        matching: find.byType(Container),
      ),
    );
    expect(disc.center.dx, 195);
    expect(tester.takeException(), isNull);
  });
}
