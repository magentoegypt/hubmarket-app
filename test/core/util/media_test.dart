import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/util/media.dart';

void main() {
  group('httpsMediaUrl', () {
    test('upgrades http to https', () {
      expect(
        httpsMediaUrl('http://hub-market.magento2.click/media/catalog/x.jpg'),
        'https://hub-market.magento2.click/media/catalog/x.jpg',
      );
    });

    test('leaves https, relative, null and empty untouched', () {
      expect(httpsMediaUrl('https://hub-market.magento2.click/media/x.jpg'),
          'https://hub-market.magento2.click/media/x.jpg');
      expect(httpsMediaUrl('/media/x.jpg'), '/media/x.jpg');
      expect(httpsMediaUrl(null), isNull);
      expect(httpsMediaUrl(''), '');
    });
  });

  group('resolveMediaUrl', () {
    const base = 'https://hub-market.magento2.click/media/';

    test('passes absolute URLs through, upgrading http', () {
      expect(
        resolveMediaUrl('https://hub-market.magento2.click/media/a.png', base),
        'https://hub-market.magento2.click/media/a.png',
      );
      expect(
        resolveMediaUrl('http://hub-market.magento2.click/media/a.png', base),
        'https://hub-market.magento2.click/media/a.png',
      );
    });

    test('joins a base-relative path onto the media base', () {
      expect(
        resolveMediaUrl('default/promo.png', base),
        'https://hub-market.magento2.click/media/default/promo.png',
      );
    });

    test('resolves a root-relative path against the origin, not the media '
        'base — joining it would duplicate /media/', () {
      expect(
        resolveMediaUrl('/media/catalog/category/beauty-cat-3.webp', base),
        'https://hub-market.magento2.click/media/catalog/category/beauty-cat-3.webp',
      );
    });

    test('upgrades an http media base to https', () {
      expect(
        resolveMediaUrl('/media/a.webp', 'http://hub-market.magento2.click/media/'),
        'https://hub-market.magento2.click/media/a.webp',
      );
      expect(
        resolveMediaUrl('default/a.png', 'http://hub-market.magento2.click/media/'),
        'https://hub-market.magento2.click/media/default/a.png',
      );
    });

    test('keeps an explicit port', () {
      expect(
        resolveMediaUrl('/media/a.webp', 'https://hubmarket.test:8443/media/'),
        'https://hubmarket.test:8443/media/a.webp',
      );
    });

    test('degrades to empty on empty input or an unusable base', () {
      expect(resolveMediaUrl('', base), '');
      expect(resolveMediaUrl(null, base), '');
      expect(resolveMediaUrl('default/a.png', ''), '');
      expect(resolveMediaUrl('/media/a.png', 'not-a-url'), '');
    });
  });

  group('webpTwinUrl', () {
    const host = 'hub-market.magento2.click';
    const resized =
        'https://$host/media/catalog/product/cache/74c1057f7991b4edb2bc7bdaa94de933/s/c/screenshot_107';

    test('is the same URL plus .webp for a resized JPEG or PNG', () {
      for (final ext in ['jpg', 'jpeg', 'png', 'JPG', 'PNG']) {
        expect(
          webpTwinUrl('$resized.$ext', storeHost: host),
          '$resized.$ext.webp',
          reason: ext,
        );
      }
    });

    test('keeps a percent-encoded file name as it is', () {
      const name =
          'https://$host/media/catalog/product/cache/74c1057f7991b4edb2bc7bdaa94de933/_/-/_-_19%20(1).jpg';
      expect(webpTwinUrl(name, storeHost: host), '$name.webp');
    });

    test('is null for another host: the uncached origin 404s a missing copy',
        () {
      expect(
        webpTwinUrl(
          'https://multi.magento2.click/media/catalog/product/cache/a/b/c.jpg',
          storeHost: host,
        ),
        isNull,
      );
      expect(webpTwinUrl('$resized.jpg', storeHost: 'multi.magento2.click'), isNull);
      expect(webpTwinUrl('$resized.jpg', storeHost: ''), isNull);
    });

    test('is null outside the resized product images — they have no copy', () {
      for (final path in [
        // the "no image" placeholder and an original upload: 404 on .webp
        '/media/catalog/product/placeholder/hm-placeholder.png',
        '/media/catalog/product/s/c/screenshot_107.jpg',
        '/media/catalog/category/shoes.jpg',
        '/media/wysiwyg/promo.png',
        '/media/ves_vendors/logo.png',
      ]) {
        expect(webpTwinUrl('https://$host$path', storeHost: host), isNull, reason: path);
      }
    });

    test('is null for other formats, an existing copy, queries and non-https',
        () {
      for (final url in [
        '$resized.gif',
        '$resized.svg',
        '$resized.webp',
        '$resized.jpg.webp',
        '$resized.jpg?width=300',
        '$resized.jpg#top',
        resized,
        'http://$host/media/catalog/product/cache/a/b/c.jpg',
        '/media/catalog/product/cache/a/b/c.jpg',
      ]) {
        expect(webpTwinUrl(url, storeHost: host), isNull, reason: url);
      }
    });

    test('is null for null and empty', () {
      expect(webpTwinUrl(null, storeHost: host), isNull);
      expect(webpTwinUrl('', storeHost: host), isNull);
    });
  });
}
