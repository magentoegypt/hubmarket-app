import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/widgets/hub_button.dart';
import 'package:hubmarket_app/core/widgets/hub_chip.dart';
import 'package:hubmarket_app/core/widgets/hub_icon_button.dart';
import 'package:hubmarket_app/core/widgets/hub_top_bar.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_card.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

Widget _app(Widget home, {String locale = 'en', double textScale = 1}) =>
    MaterialApp(
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(locale),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    );

void main() {
  group('Money.formatted', () {
    test('drops the decimals of a whole amount, as the frames draw them', () {
      expect(const Money(amount: 425, currency: 'AED').formatted(), 'AED 425');
      expect(
        const Money(amount: 1250, currency: 'AED').formatted(),
        'AED 1,250',
      );
    });

    test('keeps both digits when there are fils', () {
      expect(
        const Money(amount: 12.5, currency: 'AED').formatted(),
        'AED 12.50',
      );
      expect(
        const Money(amount: 1250.05, currency: 'AED').formatted(),
        'AED 1,250.05',
      );
    });

    test('Arabic puts the dirham sign after the number, as the frames do', () {
      addTearDown(() => Money.arabic = false);
      Money.arabic = true;

      // A right-to-left isolate around "425 د.إ" (number first, sign to its left).
      expect(
        const Money(amount: 425, currency: 'AED').formatted(),
        '⁧425 د.إ⁩',
      );
      expect(
        const Money(amount: 1250.5, currency: 'AED').formatted(),
        '⁧1,250.50 د.إ⁩',
      );
    });

    test('a float that is whole to the fils still reads whole', () {
      expect(
        const Money(amount: 543.0000001, currency: 'AED').formatted(),
        'AED 543',
      );
    });
  });

  group('HubTopBar', () {
    testWidgets('shows the title and subtitle, no back on a root route', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            appBar: HubTopBar(title: 'My cart', subtitle: '4 items · 2 stores'),
          ),
        ),
      );

      expect(find.text('My cart'), findsOneWidget);
      expect(find.text('4 items · 2 stores'), findsOneWidget);
      expect(find.byIcon(HubIcons.arrowLeft), findsNothing);
    });

    testWidgets('has a back button on a pushed route and it pops', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(
                      appBar: HubTopBar(title: 'Wishlist'),
                      body: Text('pushed'),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('pushed'), findsOneWidget);
      expect(find.byIcon(HubIcons.arrowLeft), findsOneWidget);

      await tester.tap(find.byIcon(HubIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(find.text('pushed'), findsNothing);
    });

    testWidgets('is 56 px under the status bar', (tester) async {
      await tester.pumpWidget(
        _app(const Scaffold(appBar: HubTopBar(title: 'Title'))),
      );
      // The bar fills the status bar's inset (non-zero with UI_AUDIT) plus the
      // 56 px row.
      final inset = MediaQueryData.fromView(tester.view).padding.top;
      final bar = tester.getSize(find.byType(HubTopBar));
      expect(bar.height, 56 + inset);
    });
  });

  group('HubIconButton', () {
    testWidgets('is a 40 px target with the tooltip as its label and a dot', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: HubIconButton(
                icon: HubIcons.bell,
                tooltip: 'Notifications',
                showDot: true,
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(InkWell)), const Size(40, 40));
      await tester.tap(find.byTooltip('Notifications'));
      expect(taps, 1);
    });
  });

  group('HubChip', () {
    testWidgets('is 36 px high, navy when selected, outlined when not', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const Scaffold(
            body: Row(
              children: [
                HubChip(label: 'All', selected: true),
                HubChip(label: 'Grocery'),
              ],
            ),
          ),
        ),
      );

      final chips = find.byType(HubChip);
      expect(tester.getSize(chips.first).height, 36);
      final materials = tester
          .widgetList<Material>(
            find.descendant(of: chips, matching: find.byType(Material)),
          )
          .toList();
      expect(materials.first.color, AppColors.brandPrimary);
      expect(materials.last.color, Colors.white);
      expect(
        (materials.last.shape! as StadiumBorder).side.color,
        AppColors.borderStrong,
      );
    });

    testWidgets('taps through', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: HubChip(label: 'Furniture', onTap: () => taps++),
          ),
        ),
      );
      await tester.tap(find.text('Furniture'));
      expect(taps, 1);
    });
  });

  group('HubButton', () {
    testWidgets('is 52 px high with the label, per style', (tester) async {
      for (final style in HubButtonStyle.values) {
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: Center(
                child: HubButton(
                  label: 'Add to cart',
                  style: style,
                  expand: false,
                  onPressed: () {},
                ),
              ),
            ),
          ),
        );
        expect(find.text('Add to cart'), findsOneWidget, reason: '$style');
        final button = find.ancestor(
          of: find.text('Add to cart'),
          matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is OutlinedButton || w is TextButton,
          ),
        );
        expect(tester.getSize(button).height, 52, reason: '$style');
      }
    });

    testWidgets('loading ignores taps and shows a spinner', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: HubButton(
              label: 'Place order',
              loading: true,
              onPressed: () => taps++,
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Place order'));
      expect(taps, 0);
    });
  });

  group('product grid', () {
    testWidgets('a cell is the card width + the 10 px gap + the text block', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );
      final infoHeight = ProductCardMetrics.infoHeight(captured);
      // Figma: 100 for the text block at 1x.
      expect(infoHeight, closeTo(100, 0.01));

      final delegate = productGridDelegate(captured);
      final layout = delegate.getLayout(
        const SliverConstraints(
          axisDirection: AxisDirection.down,
          growthDirection: GrowthDirection.forward,
          userScrollDirection: ScrollDirection.idle,
          scrollOffset: 0,
          precedingScrollExtent: 0,
          overlap: 0,
          remainingPaintExtent: 800,
          crossAxisExtent: 358,
          crossAxisDirection: AxisDirection.right,
          viewportMainAxisExtent: 800,
          remainingCacheExtent: 800,
          cacheOrigin: 0,
        ),
      ) as SliverGridRegularTileLayout;
      // 358 = 2 × 171 + 16.
      expect(layout.childCrossAxisExtent, 171);
      expect(layout.crossAxisStride, 187);
      expect(layout.childMainAxisExtent, 171 + 10 + infoHeight);
      expect(layout.mainAxisStride, layout.childMainAxisExtent + 18);
    });

    testWidgets('the text block grows with the text size and in Arabic', (
      tester,
    ) async {
      late BuildContext en;
      late BuildContext enLarge;
      late BuildContext ar;
      Widget probe(void Function(BuildContext) set) => Builder(
        builder: (context) {
          set(context);
          return const SizedBox();
        },
      );
      await tester.pumpWidget(_app(probe((c) => en = c)));
      final base = ProductCardMetrics.infoHeight(en);
      await tester.pumpWidget(_app(probe((c) => enLarge = c), textScale: 1.5));
      final large = ProductCardMetrics.infoHeight(enLarge);
      await tester.pumpWidget(_app(probe((c) => ar = c), locale: 'ar'));
      final arabic = ProductCardMetrics.infoHeight(ar);

      expect(large, greaterThan(base));
      expect(arabic, greaterThan(base));
    });
  });
}
