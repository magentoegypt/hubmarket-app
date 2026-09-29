import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/app_config.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_view.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';

AppConfig _config({String key = '', String appId = 'HL67ED06DQ'}) => AppConfig(
  flavor: 'dev',
  graphqlEndpoint: 'https://hub-market.magento2.click/graphql',
  defaultLocale: 'en',
  bootstrapStoreCode: 'en',
  storeCodeEn: 'en',
  storeCodeAr: 'ar',
  currency: 'AED',
  userAgent: 'HubMarketApp-test',
  algoliaAppId: appId,
  algoliaSearchKey: key,
  algoliaIndexPrefix: 'hubmarket_',
  algoliaSortReplicas: 'price_default_asc,price_default_desc,created_at_desc',
);

void main() {
  final now = DateTime.utc(2026, 9, 29, 16);

  group('algoliaConfigFromHtml', () {
    test('reads the escaped JSON.parse literal Magento renders', () {
      final config = storefrontAlgoliaConfig(store: 'ar');
      final parsed = algoliaConfigFromHtml(storefrontHtml(config));
      expect(parsed, config);
      expect(parsed!['facets'][2]['label'], 'العلامة التجارية');
    });

    test('is null for a page without it, or with a broken literal', () {
      expect(algoliaConfigFromHtml('<html><body>hi</body></html>'), isNull);
      expect(
        algoliaConfigFromHtml(
          "<script>window.algoliaConfig = JSON.parse('\\u007B\\u0022a",
        ),
        isNull,
      );
    });
  });

  group('securedKeyValidUntil', () {
    test('decodes a secured key\'s validUntil', () {
      final until = DateTime.utc(2026, 9, 30, 8, 17, 25);
      expect(securedKeyValidUntil(fakeSecuredKey(validUntil: until)), until);
    });

    test('is null for a plain search-only key or anything else', () {
      expect(securedKeyValidUntil('0123456789abcdef0123456789abcdef'), isNull);
      expect(securedKeyValidUntil('not base64 !!'), isNull);
      expect(securedKeyValidUntil(''), isNull);
      // Secured, but without a validUntil restriction.
      expect(
        securedKeyValidUntil(
          base64.encode(utf8.encode('${'ab' * 32}tagFilters=')),
        ),
        isNull,
      );
    });
  });

  group('AlgoliaSettings', () {
    test('from the storefront: indices, facets, replicas, suggestions', () {
      final until = now.add(const Duration(hours: 16));
      final settings = AlgoliaSettings.fromStorefrontConfig(
        storefrontAlgoliaConfig(apiKey: fakeSecuredKey(validUntil: until)),
      );

      expect(settings.appId, 'HL67ED06DQ');
      expect(settings.productsIndex, 'hubmarket_en_products');
      expect(settings.categoriesIndex, 'hubmarket_en_categories');
      expect(settings.pagesIndex, 'hubmarket_en_pages');
      expect(settings.priceAttribute, 'price.AED.default');
      expect(settings.validUntil, until);
      expect(settings.productSuggestions, 8);
      expect(settings.categorySuggestions, 2);
      expect(settings.pageSuggestions, 2);
      expect(settings.categorySeparator, ' /// ');
      expect(settings.facets.map((f) => f.attribute), [
        'price',
        'categories',
        'mgs_brand',
        'color',
        'seller',
        'rating_summary',
      ]);
      expect(settings.facet('mgs_brand')!.label, 'Brand');
      expect(settings.facet('price')!.isRange, isTrue);
      expect(
        settings.sorts.map((s) => (s.indexName, s.attribute, s.descending)),
        [
          ('hubmarket_en_products_price_default_asc', 'price', false),
          ('hubmarket_en_products_price_default_desc', 'price', true),
          ('hubmarket_en_products_created_at_desc', 'created_at', true),
        ],
      );
      expect(settings.fromBackend, isTrue);
    });

    test('a key is unusable from two minutes before its validUntil', () {
      AlgoliaSettings withKeyUntil(DateTime until) =>
          AlgoliaSettings.fromStorefrontConfig(
            storefrontAlgoliaConfig(apiKey: fakeSecuredKey(validUntil: until)),
          );
      expect(
        withKeyUntil(now.add(const Duration(hours: 1))).usableAt(now),
        isTrue,
      );
      expect(
        withKeyUntil(now.add(const Duration(minutes: 1))).usableAt(now),
        isFalse,
      );
      expect(
        withKeyUntil(now.subtract(const Duration(hours: 1))).usableAt(now),
        isFalse,
      );
    });

    test('lacking the key or the index is a FormatException', () {
      expect(
        () => AlgoliaSettings.fromStorefrontConfig(
          storefrontAlgoliaConfig()..remove('apiKey'),
        ),
        throwsFormatException,
      );
    });

    test('survives the offline cache round trip', () {
      final settings = AlgoliaSettings.fromStorefrontConfig(
        storefrontAlgoliaConfig(store: 'ar'),
      );
      final again = AlgoliaSettings.fromStorefrontConfig(
        jsonDecode(jsonEncode(settings.toStorefrontConfig()))
            as Map<String, dynamic>,
      );
      expect(again.indexName, 'hubmarket_ar');
      expect(again.searchKey, settings.searchKey);
      expect(again.validUntil, settings.validUntil);
      expect(again.facet('color')!.label, 'اللون');
      expect(again.sorts.last.label, 'الأحدث أولاً');
      expect(again.pageSuggestions, 2);
      expect(again.categorySeparator, ' /// ');
    });

    test('from a static key: the configured replicas, basic facets', () {
      final settings = AlgoliaSettings.fromAppConfig(
        _config(key: '0123456789abcdef0123456789abcdef'),
        'ar',
      );
      expect(settings.indexName, 'hubmarket_ar');
      expect(settings.validUntil, isNull);
      expect(settings.fromBackend, isFalse);
      expect(settings.sorts.map((s) => s.indexName), [
        'hubmarket_ar_products_price_default_asc',
        'hubmarket_ar_products_price_default_desc',
        'hubmarket_ar_products_created_at_desc',
      ]);
      expect(settings.sorts.last.attribute, 'created_at');
      expect(settings.facets.map((f) => f.attribute), [
        'price',
        'categories',
        'rating_summary',
      ]);
    });
  });

  group('AlgoliaSettingsRepository', () {
    AlgoliaSettingsRepository repository(
      FakeAlgoliaBackend backend, {
      FakeLocalCache? cache,
      AppConfig? config,
      DateTime? at,
    }) => AlgoliaSettingsRepository(
      config: config ?? _config(),
      client: backend.client,
      cache: cache ?? FakeLocalCache(),
      storefrontPage: (store) =>
          Uri.parse('https://hub-market.magento2.click/$store/'),
      clock: () => at ?? DateTime.now(),
    );

    test('reads the store view\'s page once, then remembers it', () async {
      final backend = FakeAlgoliaBackend();
      final cache = FakeLocalCache();
      final repo = repository(backend, cache: cache);

      final first = await repo.settingsFor('ar');
      final second = await repo.settingsFor('ar');

      expect(first.indexName, 'hubmarket_ar');
      expect(identical(first, second), isTrue);
      expect(backend.pageRequests, hasLength(1));
      final page = backend.pageRequests.single;
      expect(page.url.toString(), 'https://hub-market.magento2.click/ar/');
      expect(page.headers['User-Agent'], 'HubMarketApp-test');
      // Kept for the next launch.
      expect(cache.readString('algolia_settings_ar'), isNotNull);

      // A new launch reads the cache, not the page.
      final relaunched = repository(backend, cache: cache);
      expect((await relaunched.settingsFor('ar')).indexName, 'hubmarket_ar');
      expect(backend.pageRequests, hasLength(1));
    });

    test('concurrent first searches share one page load', () async {
      final backend = FakeAlgoliaBackend();
      final repo = repository(backend);
      await Future.wait([repo.settingsFor('en'), repo.settingsFor('en')]);
      expect(backend.pageRequests, hasLength(1));
    });

    test('an expired cached key is replaced from the page', () async {
      final backend = FakeAlgoliaBackend();
      final cache = FakeLocalCache();
      final expired = AlgoliaSettings.fromStorefrontConfig(
        storefrontAlgoliaConfig(
          apiKey: fakeSecuredKey(
            validUntil: DateTime.now().subtract(const Duration(minutes: 5)),
          ),
        ),
      );
      await cache.writeString(
        'algolia_settings_en',
        jsonEncode(expired.toStorefrontConfig()),
      );

      final settings = await repository(
        backend,
        cache: cache,
      ).settingsFor('en');

      expect(settings.searchKey, isNot(expired.searchKey));
      expect(backend.pageRequests, hasLength(1));
    });

    test('invalidate drops the remembered settings', () async {
      final backend = FakeAlgoliaBackend();
      final repo = repository(backend);
      await repo.settingsFor('en');
      await repo.invalidate('en');
      await repo.settingsFor('en');
      expect(backend.pageRequests, hasLength(2));
    });

    test('a static key needs no page', () async {
      final backend = FakeAlgoliaBackend();
      final settings = await repository(
        backend,
        config: _config(key: '0123456789abcdef0123456789abcdef'),
      ).settingsFor('en');
      expect(settings.fromBackend, isFalse);
      expect(backend.pageRequests, isEmpty);
    });

    test(
      'unavailable: no app id, a failing page, no config, an old key',
      () async {
        await expectLater(
          repository(
            FakeAlgoliaBackend(),
            config: _config(appId: ''),
          ).settingsFor('en'),
          throwsA(isA<AlgoliaUnavailable>()),
        );
        await expectLater(
          repository(FakeAlgoliaBackend(pageStatus: 503)).settingsFor('en'),
          throwsA(isA<AlgoliaUnavailable>()),
        );
        await expectLater(
          repository(FakeAlgoliaBackend(configs: {})).settingsFor('en'),
          throwsA(isA<AlgoliaUnavailable>()),
        );
        // A full-page-cache copy older than its key.
        final stale = FakeAlgoliaBackend(
          configs: {
            'en': storefrontAlgoliaConfig(
              apiKey: fakeSecuredKey(
                validUntil: DateTime.now().subtract(const Duration(hours: 1)),
              ),
            ),
          },
        );
        await expectLater(
          repository(stale).settingsFor('en'),
          throwsA(isA<AlgoliaUnavailable>()),
        );
      },
    );
  });

  group('storefrontHomeUri', () {
    const config = AppConfig.current;
    const state = StoreState(
      activeLocale: 'ar',
      localeToCode: {'en': 'en', 'ar': 'ar'},
      defaultLocale: 'en',
      currency: 'AED',
    );

    test('the store segment on the GraphQL host before views load', () {
      expect(
        storefrontHomeUri(state, config, 'ar').toString(),
        'https://hub-market.magento2.click/ar/',
      );
    });

    test('the active view\'s base_link_url once views load', () {
      final loaded = state.copyWith(
        stores: const [
          StoreView(
            storeCode: 'ar',
            storeName: 'Arabic',
            locale: 'ar_SA',
            isDefault: false,
            baseCurrencyCode: 'AED',
            displayCurrencyCode: 'AED',
            baseUrl: 'http://hub-market.magento2.click/',
            secureBaseUrl: 'https://hub-market.magento2.click/',
            baseMediaUrl: 'https://hub-market.magento2.click/media/',
            baseLinkUrl: 'http://hub-market.magento2.click/ar/',
          ),
        ],
      );
      expect(
        storefrontHomeUri(loaded, config, 'ar').toString(),
        'https://hub-market.magento2.click/ar/',
      );
    });
  });
}
