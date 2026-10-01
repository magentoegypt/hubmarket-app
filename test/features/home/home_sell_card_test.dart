import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/features/home/data/home_content_repository.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/hm_cms_sections.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';

const _sellHtml =
    '<h3>Sell on Hub Market</h3>'
    '<p>Open your store and reach customers nationwide — list products, manage orders and get paid from the vendor app.</p>'
    '<p><a href="https://hub-market.magento2.click/en/catalog/category/view/id/5/">Start selling</a></p>';

/// Where the block's link led.
final _visited = <String>[];

Widget _harness(
  Widget child, {
  String locale = 'en',
  GlobalKey? boundary,
}) {
  _visited.clear();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: SingleChildScrollView(child: child)),
      ),
      GoRoute(
        path: '/category/:uid',
        builder: (_, state) {
          _visited.add(state.uri.toString());
          return const Scaffold();
        },
      ),
    ],
  );
  final app = MaterialApp.router(
    routerConfig: router,
    theme: AppTheme.light(locale),
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
  return ProviderScope(
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('HmSellCard.fromBlocks', () {
    test('the heading, its line and a link-only paragraph make the card', () {
      final card = HmSellCard.fromBlocks(CmsDocument.parse(_sellHtml))!;
      expect(card.title, 'Sell on Hub Market');
      expect(card.text, startsWith('Open your store and reach customers'));
      expect(card.ctaLabel, 'Start selling');
      expect(card.ctaUrl, contains('/catalog/category/view/id/5'));
    });

    test('a heading alone is a card without a line and a button', () {
      final card = HmSellCard.fromBlocks(CmsDocument.parse('<h2>Sell with us</h2>'))!;
      expect(card.title, 'Sell with us');
      expect(card.text, isEmpty);
      expect(card.ctaLabel, isNull);
      expect(card.ctaUrl, isNull);
    });

    test('a block without a heading is not this card', () {
      expect(HmSellCard.fromBlocks(CmsDocument.parse('<p>Just a line.</p>')), isNull);
      expect(HmSellCard.fromBlocks(const <CmsBlock>[]), isNull);
    });

    test('a link inside a sentence stays part of the line', () {
      final card = HmSellCard.fromBlocks(
        CmsDocument.parse(
          '<h3>Sell</h3><p>Read the <a href="https://hub-market.magento2.click/en/terms">terms</a> first.</p>',
        ),
      )!;
      expect(card.text, 'Read the terms first.');
      expect(card.ctaLabel, isNull);
    });
  });

  group('HmCmsBlockView', () {
    for (final locale in const ['en', 'ar']) {
      testWidgets('hm_home_sell is the navy Sell card; its button follows the '
          'link ($locale)', (tester) async {
        tester.view.physicalSize = const Size(390, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _harness(
            const HmCmsBlockView(
              html: _sellHtml,
              identifier: HomeCmsBlocks.sell,
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HmSellCard), findsOneWidget);
        // Figma 07: 358 wide, 18 pt inside, the orange 40 pt store tile.
        final navy = find.descendant(
          of: find.byType(HmSellCard),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).color == AppColors.brandPrimary,
          ),
        );
        expect(tester.getSize(navy).width, 358);
        expect(find.text('Sell on Hub Market'), findsOneWidget);
        expect(find.text('Start selling'), findsOneWidget);

        await tester.tap(find.text('Start selling'));
        await tester.pumpAndSettle();
        expect(_visited, hasLength(1));
        expect(_visited.single, startsWith('/category/'));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('another block, or one without a heading, stays plain content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          const HmCmsBlockView(
            html: _sellHtml,
            identifier: 'hm_something_else',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HmSellCard), findsNothing);
      expect(find.text('Sell on Hub Market'), findsOneWidget);

      await tester.pumpWidget(
        _harness(
          const HmCmsBlockView(
            html: '<p>Only a line.</p>',
            identifier: HomeCmsBlocks.sell,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HmSellCard), findsNothing);
      expect(find.text('Only a line.'), findsOneWidget);
    });
  });
}
