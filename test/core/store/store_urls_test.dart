import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_urls.dart';
import 'package:hubmarket_app/core/store/store_view.dart';

import '../../support/fakes.dart';

StoreState _state({
  String locale = 'en',
  List<StoreView> stores = kSampleStores,
}) => StoreState(
  activeLocale: locale,
  localeToCode: const {'en': 'eg_en', 'ar': 'eg_ar'},
  defaultLocale: 'en',
  currency: 'AED',
  stores: stores,
);

void main() {
  group('productUrl', () {
    // CL042-DEV10: the PDP used to share `https://hub-market.magento2.click/<url_key>` —
    // no `.html`, no store path. urlResolver returns null for that shape, so
    // the link 404s on the web and can't be resolved back into the app.
    test('uses the active store view language path and the .html suffix', () {
      expect(
        productUrl(_state(), '6085010044712'),
        'https://hub-market.magento2.click/uae-en/6085010044712.html',
      );
    });

    test('follows the active locale to the Arabic store view', () {
      expect(
        productUrl(_state(locale: 'ar'), '6085010044712'),
        'https://hub-market.magento2.click/uae-ar/6085010044712.html',
      );
    });

    test('does not double up an existing .html suffix', () {
      expect(
        productUrl(_state(), 'clearance.html'),
        'https://hub-market.magento2.click/uae-en/clearance.html',
      );
    });

    test('is null when the url_key is empty', () {
      expect(productUrl(_state(), ''), isNull);
      expect(productUrl(_state(), '   '), isNull);
    });

    test('is null before store config loads, so callers can fall back', () {
      expect(productUrl(_state(stores: const []), 'foo'), isNull);
    });
  });

  group('storeBaseUrl', () {
    test('upgrades the http base_link_url Magento returns to https', () {
      const insecure = <StoreView>[
        StoreView(
          storeCode: 'eg_en',
          storeName: 'EN',
          locale: 'en_US',
          isDefault: true,
          baseCurrencyCode: 'AED',
          displayCurrencyCode: 'AED',
          baseUrl: 'http://hub-market.magento2.click/',
          secureBaseUrl: 'https://hub-market.magento2.click/',
          baseMediaUrl: 'http://hub-market.magento2.click/media/',
          baseLinkUrl: 'http://hub-market.magento2.click/uae-en/',
        ),
      ];
      expect(
        storeBaseUrl(_state(stores: insecure)),
        'https://hub-market.magento2.click/uae-en/',
      );
    });

    test('adds the missing separator rather than concatenating blindly', () {
      const noSlash = <StoreView>[
        StoreView(
          storeCode: 'eg_en',
          storeName: 'EN',
          locale: 'en_US',
          isDefault: true,
          baseCurrencyCode: 'AED',
          displayCurrencyCode: 'AED',
          baseUrl: 'https://hub-market.magento2.click',
          secureBaseUrl: 'https://hub-market.magento2.click',
          baseMediaUrl: 'https://hub-market.magento2.click/media/',
          baseLinkUrl: 'https://hub-market.magento2.click/uae-en',
        ),
      ];
      expect(
        productUrl(_state(stores: noSlash), 'foo'),
        'https://hub-market.magento2.click/uae-en/foo.html',
      );
    });

    test('falls back to secure_base_url when base_link_url is absent', () {
      const noLink = <StoreView>[
        StoreView(
          storeCode: 'eg_en',
          storeName: 'EN',
          locale: 'en_US',
          isDefault: true,
          baseCurrencyCode: 'AED',
          displayCurrencyCode: 'AED',
          baseUrl: 'https://hub-market.magento2.click/',
          secureBaseUrl: 'https://hub-market.magento2.click/',
          baseMediaUrl: 'https://hub-market.magento2.click/media/',
        ),
      ];
      expect(
        productUrl(_state(stores: noLink), 'foo'),
        'https://hub-market.magento2.click/foo.html',
      );
    });
  });

  group('localeForStoreUrl', () {
    // The path segment is `uae-ar` while the store code is `eg_ar` — it must be
    // matched against base_link_url, never guessed from the code.
    test('maps the store path segment to the app language', () {
      expect(
        localeForStoreUrl(
          _state(),
          'https://hub-market.magento2.click/uae-ar/fragrance/6085010044712.html',
        ),
        'ar',
      );
      expect(
        localeForStoreUrl(_state(), 'https://hub-market.magento2.click/uae-en/clearance.html'),
        'en',
      );
    });

    test('is null for a root-level link that carries no store segment', () {
      expect(
        localeForStoreUrl(_state(), 'https://hub-market.magento2.click/clearance.html'),
        isNull,
      );
    });

    test('is null for an unrecognised first segment', () {
      expect(
        localeForStoreUrl(_state(), 'https://hub-market.magento2.click/media/catalog/x.jpg'),
        isNull,
      );
    });
  });
}
