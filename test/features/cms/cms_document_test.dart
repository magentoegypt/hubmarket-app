import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/features/cms/domain/cms_links.dart';
import 'package:hubmarket_app/features/cms/presentation/widgets/cms_html_view.dart';

import '../../support/fakes.dart';

void main() {
  group('CmsDocument.parse', () {
    test('headings, paragraphs and inline formatting', () {
      final blocks = CmsDocument.parse(
        '<h2 id="collect">What we collect</h2>'
        '<p>Your <strong>name</strong>, <em>address</em> and '
        '<a href="/en/contact/">contact</a> details.</p>',
      );
      expect(blocks, hasLength(2));
      final heading = blocks[0] as CmsHeading;
      expect(heading.level, 2);
      expect(heading.text, 'What we collect');
      expect(heading.anchor, 'collect');

      final p = blocks[1] as CmsParagraph;
      expect(p.text, 'Your name, address and contact details.');
      expect(p.inlines.firstWhere((r) => r.text == 'name').bold, isTrue);
      expect(p.inlines.firstWhere((r) => r.text == 'address').italic, isTrue);
      expect(
        p.inlines.firstWhere((r) => r.text == 'contact').href,
        '/en/contact/',
      );
    });

    test('collapses whitespace and keeps <br> as a line break', () {
      final p =
          CmsDocument.parse('<p>  Line one \n  <br/>\n   line   two  </p>')
                  .single
              as CmsParagraph;
      expect(p.text, 'Line one\nline two');
    });

    test('nested lists stay nested, ordered lists are ordered', () {
      final list =
          CmsDocument.parse(
                '<ol><li>First<ul><li>Inner</li></ul></li><li>Second</li></ol>',
              ).single
              as CmsList;
      expect(list.ordered, isTrue);
      expect(list.items, hasLength(2));
      expect((list.items[0][0] as CmsParagraph).text, 'First');
      final inner = list.items[0][1] as CmsList;
      expect(inner.ordered, isFalse);
      expect((inner.items.single.single as CmsParagraph).text, 'Inner');
    });

    test('flattens layout wrappers and drops scripts, styles and forms', () {
      final blocks = CmsDocument.parse(
        '<div class="customer-service cms-content"><div class="row">'
        '<p>Kept</p></div><script>alert(1)</script><style>p{}</style>'
        '<form><input name="q"></form></div>',
      );
      expect(blocks, hasLength(1));
      expect((blocks.single as CmsParagraph).text, 'Kept');
    });

    test('tables keep caption, header cells and rows', () {
      final table =
          CmsDocument.parse(
                '<table><caption>Shipping</caption><thead><tr><th>Total</th>'
                '<th>Standard</th></tr></thead><tbody><tr><th>Up to 200</th>'
                '<td>16</td></tr></tbody></table>',
              ).single
              as CmsTable;
      expect(CmsDocument.inlineText(table.caption), 'Shipping');
      expect(table.rows, hasLength(2));
      expect(table.columnCount, 2);
      expect(table.rows[0].every((c) => c.header), isTrue);
      expect(CmsDocument.inlineText(table.rows[1][1].inlines), '16');
    });

    test('images, linked images and images inside a paragraph', () {
      final blocks = CmsDocument.parse(
        '<p>Intro<img src="https://x.test/a.jpg" alt="A" width="400" height="200"></p>'
        '<a href="/en/sale.html"><img src="/media/b.png"></a>',
      );
      expect((blocks[0] as CmsParagraph).text, 'Intro');
      final a = blocks[1] as CmsImage;
      expect(a.src, 'https://x.test/a.jpg');
      expect(a.alt, 'A');
      expect(a.width, 400);
      expect(a.height, 200);
      final b = blocks[2] as CmsImage;
      expect(b.src, '/media/b.png');
      expect(b.href, '/en/sale.html');
    });

    test('sections are the h2s; anchors resolve to their block', () {
      final blocks = CmsDocument.parse(
        '<p>Intro</p><h2 id="a">One</h2><p>x</p><h2 id="b">Two</h2><p>y</p>',
      );
      expect(
        CmsDocument.sections(blocks).map((s) => s.title),
        ['One', 'Two'],
      );
      expect(CmsDocument.anchorIndex(blocks, 'b'), 3);
      expect(CmsDocument.anchorIndex(blocks, 'missing'), isNull);
    });

    test('a single heading is not navigation', () {
      expect(
        CmsDocument.sections(CmsDocument.parse('<h2>Only</h2><p>x</p>')),
        isEmpty,
      );
    });

    test('empty or whitespace-only markup yields nothing', () {
      expect(CmsDocument.parse(''), isEmpty);
      expect(CmsDocument.parse('<div>  \n </div><p> </p>'), isEmpty);
    });
  });

  group('storefront links', () {
    test('footer legal links keep their labels and URLs', () {
      final links = linksFromHtml(kLegalLinksBlock);
      expect(links.map((l) => l.label), ['Privacy', 'Terms', 'Cookies']);
      expect(
        links.first.url,
        'https://hub-market.magento2.click/en/privacy-policy-cookie-restriction-mode/',
      );
    });

    test('storePathOf strips host, store segment and slashes', () {
      expect(
        storePathOf(
          'https://hub-market.magento2.click/en/privacy-policy-cookie-restriction-mode/',
        ),
        'privacy-policy-cookie-restriction-mode',
      );
      expect(
        storePathOf('https://hub-market.magento2.click/ar/customer-service/'),
        'customer-service',
      );
      expect(storePathOf('/en/company/about-us/?x=1#top'), 'company/about-us');
      expect(storePathOf('about-us'), 'about-us');
      expect(storePathOf('https://hub-market.magento2.click/en/'), '');
    });
  });

  group('CmsHtmlView', () {
    Future<List<String>> pumpAndTapLink(WidgetTester tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CmsHtmlView(
                blocks: CmsDocument.parse(
                  '<h2>Your choices</h2>'
                  '<p>Read our <a href="https://x.test/terms">terms</a>.</p>'
                  '<ul><li>One</li><li>Two</li></ul>'
                  '<table><tr><th>Cookie</th><th>Use</th></tr>'
                  '<tr><td>CART</td><td>Your cart</td></tr></table>',
                ),
                onLink: tapped.add,
              ),
            ),
          ),
        ),
      );
      return tapped;
    }

    testWidgets('renders headings, lists and tables natively', (tester) async {
      await pumpAndTapLink(tester);
      expect(find.text('Your choices'), findsOneWidget);
      expect(find.text('•'), findsNWidgets(2));
      expect(find.text('One'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('CART'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tapped link reports its href', (tester) async {
      final tapped = await pumpAndTapLink(tester);
      final paragraph = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText() == 'Read our terms.',
      );
      expect(paragraph, findsOneWidget);
      // Only the link run carries a recognizer; fire it as a tap would.
      final spans = <TextSpan>[];
      tester.widget<RichText>(paragraph).text.visitChildren((span) {
        if (span is TextSpan && span.recognizer != null) spans.add(span);
        return true;
      });
      expect(spans.map((s) => s.text), ['terms']);
      (spans.single.recognizer! as TapGestureRecognizer).onTap!();
      expect(tapped, ['https://x.test/terms']);
    });
  });
}
