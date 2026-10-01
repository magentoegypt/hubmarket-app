import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

const _url = 'https://hub-market.magento2.click/media/catalog/product/cache/abc/a/t/x.jpg';

Widget _wrap(Widget child, {double dpr = 3}) => MediaQuery(
  data: MediaQueryData(devicePixelRatio: dpr),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  ),
);

void main() {
  group('HubImage', () {
    testWidgets('a null or empty url never reaches the network', (tester) async {
      for (final url in <String?>[null, '']) {
        await tester.pumpWidget(
          _wrap(SizedBox(width: 100, height: 100, child: HubImage(url: url))),
        );
        expect(find.byType(CachedNetworkImage), findsNothing);
        // Falls back to the "no image" state, not a blank hole.
        expect(find.byIcon(HubIcons.image), findsOneWidget);
      }
    });

    testWidgets('an image never fades — a cached one must appear instantly', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(width: 100, height: 100, child: HubImage(url: _url)),
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      // Regression lock. cached_network_image defaults to 500ms in / 1000ms
      // out, which left disk-cached images visibly veiled for about a second
      // (CL042-DEV07). Nothing may reintroduce a transition here.
      expect(image.fadeInDuration, Duration.zero);
      expect(image.fadeOutDuration, Duration.zero);
      expect(image.placeholderFadeInDuration, Duration.zero);
    });

    testWidgets('decodes at the on-screen size, not the source resolution', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const HubImage(url: _url, decodeWidth: 56), dpr: 3),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.memCacheWidth, 168); // 56 logical px x DPR 3
      // Never both axes — that would distort the aspect ratio.
      expect(image.memCacheHeight, isNull);
    });

    testWidgets('falls back to the laid-out width when no size is given', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(width: 120, height: 200, child: HubImage(url: _url)),
          dpr: 2,
        ),
      );

      final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(image.memCacheWidth, 240);
    });
  });

  group('HubImage and the WebP copy', () {
    // Pinned, so these don't depend on a --dart-define of the endpoint.
    setUp(() {
      HubImage.webpHost = 'hub-market.magento2.click';
      HubImage.forgetWebpMisses();
    });
    tearDown(HubImage.forgetWebpMisses);

    CachedNetworkImage shown(WidgetTester tester) =>
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));

    Future<void> pumpImage(WidgetTester tester, String url) => tester.pumpWidget(
      _wrap(SizedBox(width: 100, height: 100, child: HubImage(url: url))),
    );

    testWidgets('asks for the .webp copy of a resized product image', (
      tester,
    ) async {
      await pumpImage(tester, _url);
      expect(shown(tester).imageUrl, '$_url.webp');
    });

    testWidgets('leaves every other image as it is', (tester) async {
      for (final url in [
        'https://hub-market.magento2.click/media/catalog/product/placeholder/hm-placeholder.png',
        'https://hub-market.magento2.click/media/catalog/product/s/c/original.jpg',
        'https://hub-market.magento2.click/media/wysiwyg/promo.png',
        'https://multi.magento2.click/media/catalog/product/cache/abc/a/t/x.jpg',
        'https://example.com/media/catalog/product/cache/abc/a/t/x.jpg',
      ]) {
        await pumpImage(tester, url);
        expect(shown(tester).imageUrl, url);
      }
    });

    testWidgets('a copy that fails to load falls back to the original, '
        'and the miss is remembered', (tester) async {
      await pumpImage(tester, _url);
      final first = shown(tester);
      expect(first.imageUrl, '$_url.webp');

      // What the 404 of a copy that is not made yet leads to.
      final context = tester.element(find.byType(CachedNetworkImage));
      final fallback = first.errorWidget!(context, first.imageUrl, 'HTTP 404');
      await tester.pumpWidget(_wrap(fallback));
      expect(shown(tester).imageUrl, _url);

      // Scrolling back to it, or opening it elsewhere, no longer asks twice.
      await pumpImage(tester, _url);
      expect(shown(tester).imageUrl, _url);
      expect((HubImage.provider(_url) as CachedNetworkImageProvider).url, _url);
    });

    testWidgets('an image without a copy shows the error state when it '
        'fails, as before', (tester) async {
      const placeholder =
          'https://hub-market.magento2.click/media/catalog/product/placeholder/hm-placeholder.png';
      await pumpImage(tester, placeholder);
      final image = shown(tester);
      final context = tester.element(find.byType(CachedNetworkImage));
      await tester.pumpWidget(
        _wrap(image.errorWidget!(context, image.imageUrl, 'HTTP 404')),
      );
      expect(find.byIcon(HubIcons.image), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    test('the pre-warm asks for the same copy the widget does', () {
      expect(
        (HubImage.provider(_url) as CachedNetworkImageProvider).url,
        '$_url.webp',
      );
      final sized = HubImage.provider(_url, decodeWidth: 300) as ResizeImage;
      expect((sized.imageProvider as CachedNetworkImageProvider).url, '$_url.webp');
    });
  });

  group('HubImage.provider', () {
    test('same url + width produce an equal (cache-hitting) key', () {
      // This is what makes precacheImage() worth anything: the pre-warm and
      // the widget must resolve to the same ImageCache key.
      expect(
        HubImage.provider(_url, decodeWidth: 300),
        equals(HubImage.provider(_url, decodeWidth: 300)),
      );
      expect(
        HubImage.provider(_url, decodeWidth: 300).hashCode,
        equals(HubImage.provider(_url, decodeWidth: 300).hashCode),
      );
    });

    test('a different decode width is a different key', () {
      expect(
        HubImage.provider(_url, decodeWidth: 300),
        isNot(equals(HubImage.provider(_url, decodeWidth: 301))),
      );
    });

    test('no decode width resolves at full size', () {
      expect(HubImage.provider(_url), isA<CachedNetworkImageProvider>());
      expect(
        HubImage.provider(_url, decodeWidth: 300),
        isA<ResizeImage>(),
      );
      // A zero/negative width is treated as "unset" rather than crashing.
      expect(
        HubImage.provider(_url, decodeWidth: 0),
        isA<CachedNetworkImageProvider>(),
      );
    });
  });
}
