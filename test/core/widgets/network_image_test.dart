import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';

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
        expect(find.byIcon(Icons.image_outlined), findsOneWidget);
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
