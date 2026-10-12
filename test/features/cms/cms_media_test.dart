import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/features/cms/presentation/widgets/cms_html_view.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/pdp_fixtures.dart';

// QA TC102: "added media (an image or a video in the short or long description)
// does not show on the app". The markup below is what the live store sends,
// trimmed from its products.

/// Page Builder's Image element (live, "Basic Bedsheet"): a desktop and a mobile
/// copy of the one file, shown one at a time by CSS.
const _pageBuilderImage =
    '<figure data-content-type="image" data-appearance="full-width" '
    'data-element="main" data-pb-style="OKWCNA0">'
    '<img class="pagebuilder-mobile-hidden" '
    'src="https://hub-market.magento2.click/media/wysiwyg/images_2_.jpg" '
    'alt="" title="" width="" height="" data-element="desktop_image" '
    'data-pb-style="BY5VW7B">'
    '<img class="pagebuilder-mobile-only" '
    'src="https://hub-market.magento2.click/media/wysiwyg/images_2_.jpg" '
    'alt="" title="" width="" height="" data-element="mobile_image" '
    'data-pb-style="JY4DMJ1"></figure>';

/// Its Video element with a YouTube player (live, "Bose 700").
const _pageBuilderYoutube =
    '<div data-content-type="video" data-appearance="default" '
    'data-element="main"><div class="pagebuilder-video-inner" '
    'data-element="inner"><div class="pagebuilder-video-wrapper" '
    'data-element="wrapper"><div class="pagebuilder-video-container">'
    '<iframe frameborder="0" allowfullscreen="" '
    'src="https://www.youtube.com/embed/Rl6EvEeN348?autoplay=1&amp;mute=1" '
    'autoplay="true" muted="true" data-element="video"></iframe>'
    '</div></div></div></div>';

/// ... and with a file (live, "Samsung 65-Inch Television").
const _pageBuilderFile =
    '<div data-content-type="video" data-appearance="default" '
    'data-element="main"><div class="pagebuilder-video-inner" '
    'data-element="inner"><div class="pagebuilder-video-wrapper" '
    'data-element="wrapper"><div class="pagebuilder-video-container">'
    '<video frameborder="0" controls="" '
    'src="https://images.samsung.com/is/content/samsung/p6pim/eg/feature/'
    '164391923/eg-feature--lrm--535244016.mp4" autoplay="true" muted="true" '
    'data-element="video"></video></div></div></div></div>';

const _youtubeWatch = 'https://www.youtube.com/watch?v=Rl6EvEeN348';

List<CmsImage> _images(List<CmsBlock> blocks) =>
    blocks.whereType<CmsImage>().toList();

List<CmsVideo> _videos(List<CmsBlock> blocks) =>
    blocks.whereType<CmsVideo>().toList();

String _text(CmsBlock block) => (block as CmsParagraph).text;

void main() {
  group('pictures', () {
    test('Page Builder draws a picture once, not its desktop and mobile copy', () {
      final blocks = CmsDocument.parse(_pageBuilderImage);
      expect(blocks, hasLength(1));
      expect(
        (blocks.single as CmsImage).src,
        'https://hub-market.magento2.click/media/wysiwyg/images_2_.jpg',
      );
    });

    test('a picture with one copy only keeps it, whichever copy it is', () {
      expect(
        _images(
          CmsDocument.parse(
            '<img class="pagebuilder-mobile-hidden" src="https://x.test/d.jpg">',
          ),
        ).single.src,
        'https://x.test/d.jpg',
      );
      expect(
        _images(
          CmsDocument.parse(
            '<img class="pagebuilder-mobile-only" src="https://x.test/m.jpg">',
          ),
        ).single.src,
        'https://x.test/m.jpg',
      );
    });

    test('the desktop copy stays when its mobile twin has no picture', () {
      final blocks = CmsDocument.parse(
        '<figure><img class="pagebuilder-mobile-hidden" '
        'src="https://x.test/d.jpg">'
        '<img class="pagebuilder-mobile-only" src=""></figure>',
      );
      expect(_images(blocks).map((i) => i.src), ['https://x.test/d.jpg']);
    });

    test('the mobile copy wins when the two differ', () {
      final blocks = CmsDocument.parse(
        '<figure><img class="pagebuilder-mobile-hidden" '
        'src="https://x.test/wide.jpg">'
        '<img class="pagebuilder-mobile-only" src="https://x.test/tall.jpg">'
        '</figure>',
      );
      expect(_images(blocks).map((i) => i.src), ['https://x.test/tall.jpg']);
    });

    test('a lazy-loaded picture is read from data-src, not its placeholder', () {
      final blocks = CmsDocument.parse(
        '<img src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" '
        'data-src="https://x.test/real.jpg">'
        '<img src="/static/loader.gif" data-lazy-src="https://x.test/two.jpg">',
      );
      expect(_images(blocks).map((i) => i.src), [
        'https://x.test/real.jpg',
        'https://x.test/two.jpg',
      ]);
    });

    test('a picture with only a srcset uses its first candidate', () {
      final blocks = CmsDocument.parse(
        '<img srcset="https://x.test/a.jpg 1x, https://x.test/b.jpg 2x">',
      );
      expect(_images(blocks).single.src, 'https://x.test/a.jpg');
    });

    test('only http(s) pictures and store paths load', () {
      final blocks = CmsDocument.parse(
        '<img src="javascript:alert(1)">'
        '<img src="data:image/png;base64,AAAA">'
        '<img src="file:///sdcard/a.jpg">'
        '<img src="//cdn.test/a.jpg">'
        '<img src="/media/wysiwyg/b.jpg">'
        '<img src="media/wysiwyg/c.jpg">'
        '<img src="http://x.test/d.jpg">',
      );
      expect(_images(blocks).map((i) => i.src), [
        'https://cdn.test/a.jpg',
        '/media/wysiwyg/b.jpg',
        'media/wysiwyg/c.jpg',
        'http://x.test/d.jpg',
      ]);
    });

    test('a picture in an inline wrapper or a <picture> still shows', () {
      final blocks = CmsDocument.parse(
        '<div><span><img src="https://x.test/a.jpg"></span></div>'
        '<p><span><img src="https://x.test/b.jpg"></span></p>'
        '<picture><source srcset="https://x.test/c.webp">'
        '<img src="https://x.test/c.jpg"></picture>',
      );
      expect(_images(blocks).map((i) => i.src), [
        'https://x.test/a.jpg',
        'https://x.test/b.jpg',
        'https://x.test/c.jpg',
      ]);
    });

    test('a picture keeps the words around it, in order', () {
      final blocks = CmsDocument.parse(
        '<p>Before <img src="https://x.test/a.jpg"></p><p>After</p>',
      );
      expect(blocks, hasLength(3));
      expect(_text(blocks[0]), 'Before');
      expect(blocks[1], isA<CmsImage>());
      expect(_text(blocks[2]), 'After');
    });
  });

  group('markup written as text', () {
    test("Page Builder's HTML Code element is read as markup", () {
      // Live ("Samsung Galaxy A23"): the seller's own HTML, entity-encoded.
      final blocks = CmsDocument.parse(
        '<div data-content-type="html" data-appearance="default" '
        'data-element="main">&lt;div&gt;Upgrade your photos&lt;/div&gt; '
        '&lt;div&gt;&nbsp;&lt;/div&gt; &lt;div&gt;Fifty megapixels&lt;/div&gt;'
        '&lt;img src="https://x.test/a.jpg"&gt;</div>',
      );
      expect(blocks.whereType<CmsParagraph>().map((p) => p.text), [
        'Upgrade your photos',
        'Fifty megapixels',
      ]);
      expect(_images(blocks).single.src, 'https://x.test/a.jpg');
    });

    test('an Arabic description that is encoded from its first tag', () {
      final blocks = CmsDocument.parse(
        '&lt;p&gt;فستان كريب ناعم&lt;/p&gt;&lt;ul&gt;&lt;li&gt;كم قصير&lt;/li&gt;'
        '&lt;/ul&gt;',
      );
      expect(_text(blocks.first), 'فستان كريب ناعم');
      expect(blocks.last, isA<CmsList>());
    });

    test('encoded formatting inside a paragraph keeps its style', () {
      final p =
          CmsDocument.parse('<p>Sizes: &lt;strong&gt;S&lt;/strong&gt; to XL</p>')
              .single
          as CmsParagraph;
      expect(p.text, 'Sizes: S to XL');
      expect(p.inlines.firstWhere((r) => r.text == 'S').bold, isTrue);
    });

    test('a comparison in plain words is not markup', () {
      final p =
          CmsDocument.parse('<p>Fits sizes 3 &lt; 5 and weights 7 &gt; 2 kg</p>')
              .single
          as CmsParagraph;
      expect(p.text, 'Fits sizes 3 < 5 and weights 7 > 2 kg');
    });

    test('text that keeps decoding to more markup stops after a few levels', () {
      // Each level is a paragraph whose text is the markup of the level below.
      String nest(int levels) {
        var html = 'deep';
        for (var i = 0; i < levels; i++) {
          final encoded = html
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
          html = '<p>$encoded</p>';
        }
        return html;
      }

      expect(CmsDocument.plainText(CmsDocument.parse(nest(3))), 'deep');
      // Far deeper than anyone writes: it ends, and what is left is plain text.
      final deep = CmsDocument.plainText(CmsDocument.parse(nest(40)));
      expect(deep, contains('deep'));
    });
  });

  group('videos', () {
    test('are dropped unless the caller asks for them, as before', () {
      expect(CmsDocument.parse(_pageBuilderYoutube), isEmpty);
      expect(CmsDocument.parse(_pageBuilderFile), isEmpty);
      expect(
        CmsDocument.parse('<p>Text</p>$_pageBuilderYoutube').single,
        isA<CmsParagraph>(),
      );
    });

    test("Page Builder's YouTube element becomes a clean watch link", () {
      final video =
          _videos(CmsDocument.parse(_pageBuilderYoutube, embeds: true)).single;
      expect(video.url, _youtubeWatch);
      expect(video.poster, isNull);
    });

    test("Page Builder's file element keeps the file's own address", () {
      final video =
          _videos(CmsDocument.parse(_pageBuilderFile, embeds: true)).single;
      expect(
        video.url,
        'https://images.samsung.com/is/content/samsung/p6pim/eg/feature/'
        '164391923/eg-feature--lrm--535244016.mp4',
      );
    });

    test('a <video> may name its file in a <source>, and a poster', () {
      final video =
          _videos(
            CmsDocument.parse(
              '<video controls poster="/media/wysiwyg/poster.jpg" '
              'title="Unboxing"><source src="clip.webm" type="video/webm">'
              '<source src="https://x.test/clip.mp4" type="video/mp4"></video>',
              embeds: true,
            ),
          ).single;
      // The MP4: WebM does not play on iOS.
      expect(video.url, 'https://x.test/clip.mp4');
      expect(video.poster, '/media/wysiwyg/poster.jpg');
      expect(video.title, 'Unboxing');
    });

    test('without an MP4 among the sources, the first one is used', () {
      final video =
          _videos(
            CmsDocument.parse(
              '<video><source src="javascript:alert(1)">'
              '<source src="clip.webm" type="video/webm">'
              '<source src="clip.ogv" type="video/ogg"></video>',
              embeds: true,
            ),
          ).single;
      expect(video.url, 'clip.webm');
    });

    test('a player page pasted into a <video> is played on its own page', () {
      final video =
          _videos(
            CmsDocument.parse(
              '<video src="https://www.youtube.com/embed/Rl6EvEeN348"></video>',
              embeds: true,
            ),
          ).single;
      expect(video.url, _youtubeWatch);
    });

    test('only players the app knows are kept; maps, forms and scripts stay out', () {
      final blocks = CmsDocument.parse(
        '<p>Find us</p>'
        '<iframe src="https://www.google.com/maps/embed?pb=1"></iframe>'
        '<iframe src="https://evil.example/embed/Rl6EvEeN348"></iframe>'
        '<iframe src="javascript:alert(1)"></iframe>'
        '<iframe src="https://www.youtube.com/embed/Rl6EvEeN348" '
        'title="Tour"></iframe>'
        '<script>alert(1)</script><embed src="https://x.test/a.swf">'
        '<object data="https://x.test/b.swf"></object><audio src="a.mp3"></audio>',
        embeds: true,
      );
      expect(blocks, hasLength(2));
      expect(_text(blocks.first), 'Find us');
      final video = blocks.last as CmsVideo;
      expect(video.url, _youtubeWatch);
      expect(video.title, 'Tour');
    });

    test('a <video> with nothing to play, or something unsafe, is dropped', () {
      expect(
        CmsDocument.parse(
          '<video controls></video>'
          '<video src="javascript:alert(1)"></video>'
          '<video src="data:video/mp4;base64,AAAA"></video>',
          embeds: true,
        ),
        isEmpty,
      );
    });

    test('a protocol-relative file gets https', () {
      expect(
        _videos(
          CmsDocument.parse('<video src="//cdn.test/a.mp4"></video>', embeds: true),
        ).single.url,
        'https://cdn.test/a.mp4',
      );
    });

    test('a player inside a paragraph follows the paragraph text', () {
      final blocks = CmsDocument.parse(
        '<p>Watch it<iframe src="https://youtu.be/Rl6EvEeN348"></iframe></p>',
        embeds: true,
      );
      expect(blocks, hasLength(2));
      expect(_text(blocks[0]), 'Watch it');
      expect((blocks[1] as CmsVideo).url, _youtubeWatch);
    });

    test('the title of a video is part of the searchable text', () {
      final blocks = CmsDocument.parse(
        '<iframe src="https://youtu.be/Rl6EvEeN348" title="Setup guide"></iframe>',
        embeds: true,
      );
      expect(CmsDocument.plainText(blocks), 'Setup guide');
    });
  });

  group('CmsHtmlView draws them', () {
    quietNetworkImages();

    Widget app(Widget child, {String locale = 'en', double width = 300}) =>
        MaterialApp(
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: SingleChildScrollView(
              child: Center(child: SizedBox(width: width, child: child)),
            ),
          ),
        );

    testWidgets('a video is a card that reports its address when tapped', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse(_pageBuilderYoutube, embeds: true),
            onLink: tapped.add,
          ),
        ),
      );

      expect(find.text('Watch video'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // 16:9, at the width it is given.
      expect(
        tester.getSize(find.byType(AspectRatio).first),
        const Size(300, 168.75),
      );
      await tester.tap(find.text('Watch video'));
      expect(tapped, [_youtubeWatch]);
    });

    testWidgets('a title replaces the label; a store path is made absolute', (
      tester,
    ) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: const [
              CmsVideo(url: '/media/wysiwyg/clip.mp4', title: 'Unboxing'),
            ],
            mediaBase: 'https://hub-market.magento2.click',
            onLink: tapped.add,
          ),
        ),
      );

      expect(find.text('Unboxing'), findsOneWidget);
      expect(find.text('Watch video'), findsNothing);
      await tester.tap(find.text('Unboxing'));
      expect(tapped, ['https://hub-market.magento2.click/media/wysiwyg/clip.mp4']);
    });

    testWidgets('a video that cannot be placed draws nothing', (tester) async {
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: const [CmsVideo(url: '/media/wysiwyg/clip.mp4')],
            onLink: (_) {},
          ),
        ),
      );
      expect(find.text('Watch video'), findsNothing);
      expect(find.byType(AspectRatio), findsNothing);
    });

    testWidgets('a poster sits behind the play button', (tester) async {
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: const [
              CmsVideo(
                url: 'https://x.test/clip.mp4',
                poster: 'https://x.test/poster.jpg',
              ),
            ],
            onLink: (_) {},
          ),
        ),
      );
      expect(find.byType(HubImage), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('the card speaks Arabic and is a button for a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse(_pageBuilderYoutube, embeds: true),
            onLink: (_) {},
          ),
          locale: 'ar',
        ),
      );
      expect(find.text('شاهد الفيديو'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('شاهد الفيديو')),
        isSemantics(
          label: 'شاهد الفيديو',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });

    testWidgets('other pages keep the 180 px strip for a picture', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse('<img src="https://x.test/a.jpg">'),
            onLink: (_) {},
          ),
        ),
      );
      expect(tester.getSize(find.byType(ClipRRect)), const Size(300, 180));
    });

    testWidgets('full-width pictures take the width, in 16:9 until they arrive', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse('<img src="https://x.test/a.jpg">'),
            onLink: (_) {},
            fullWidthImages: true,
          ),
        ),
      );
      expect(tester.getSize(find.byType(ClipRRect)), const Size(300, 168.75));
    });

    testWidgets('a picture that states its size is no wider than that', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse(
              '<img src="https://x.test/a.jpg" width="200" height="100">'
              '<img src="https://x.test/b.jpg" width="900" height="300">',
            ),
            onLink: (_) {},
            fullWidthImages: true,
          ),
        ),
      );
      final sizes = tester
          .widgetList(find.byType(ClipRRect))
          .map((w) => tester.getSize(find.byWidget(w)))
          .toList();
      // 200 x 100 as stated; 900 x 300 squeezed to the 300 it has, still 3:1.
      expect(sizes, [const Size(200, 100), const Size(300, 100)]);
    });

    testWidgets('a linked picture reports its link', (tester) async {
      final tapped = <String>[];
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse(
              '<a href="/en/sale.html"><img src="https://x.test/a.jpg"></a>',
            ),
            onLink: tapped.add,
            fullWidthImages: true,
          ),
        ),
      );
      await tester.tap(find.byType(ClipRRect));
      expect(tapped, ['/en/sale.html']);
    });

    testWidgets('a screen can set the type of the text', (tester) async {
      await tester.pumpWidget(
        app(
          CmsHtmlView(
            blocks: CmsDocument.parse('<p>Hello</p><ul><li>One</li></ul>'),
            onLink: (_) {},
            bodyStyle: const TextStyle(
              fontSize: 21,
              color: Color(0xFF123456),
            ),
          ),
        ),
      );
      TextStyle? styleOf(String text) {
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText() == text,
          ),
        );
        // `Text.rich` puts the ambient style on a root span; the view's own
        // style is on its child.
        final root = rich.text as TextSpan;
        return (root.children!.single as TextSpan).style;
      }

      expect(styleOf('Hello')?.fontSize, 21);
      expect(styleOf('Hello')?.color, const Color(0xFF123456));
      expect(styleOf('One')?.fontSize, 21);
    });
  });
}
