import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/app_config.dart';

void main() {
  group('AppConfig.current (compile-time defaults)', () {
    const config = AppConfig.current;

    test('uses sane defaults when no dart-defines are provided', () {
      expect(config.flavor, 'dev');
      expect(config.defaultLocale, 'en');
      expect(config.currency, 'AED');
      expect(config.bootstrapStoreCode, 'en');
      expect(
        config.graphqlEndpoint,
        'https://hub-market.magento2.click/graphql',
      );
    });

    test('exposes provisional locale -> store_code fallback', () {
      expect(config.provisionalStoreCodes, {'en': 'en', 'ar': 'ar'});
    });

    test('isProd reflects the flavor', () {
      expect(config.isProd, isFalse);
    });

    test('Algolia: the storefront application and prefix, no static key', () {
      expect(config.algoliaAppId, 'HL67ED06DQ');
      expect(config.algoliaIndexPrefix, 'hubmarket_');
      // The storefront's key expires daily, so none ships in the app.
      expect(config.algoliaSearchKey, isEmpty);
      expect(config.algoliaConfigured, isTrue);
      expect(config.algoliaSortReplicaSuffixes, [
        'price_default_asc',
        'price_default_desc',
        'created_at_desc',
      ]);
    });

    test('User-Agent has no version until the build is read', () {
      expect(config.userAgent, 'HubMarketApp-dev (Flutter)');
      expect(config.userAgent, AppConfig.userAgentFor('dev', null));
    });
  });

  group('User-Agent', () {
    test('names the flavor outside prod and the version when known', () {
      expect(
        AppConfig.userAgentFor('prod', '1.0.0'),
        'HubMarketApp/1.0.0 (Flutter)',
      );
      expect(
        AppConfig.userAgentFor('staging', '1.0.0'),
        'HubMarketApp-staging/1.0.0 (Flutter)',
      );
      expect(AppConfig.userAgentFor('prod', ' '), 'HubMarketApp (Flutter)');
    });

    test(
      'forVersion puts the installed version in, and changes nothing else',
      () {
        final config = AppConfig.forVersion('1.0.0');
        expect(config.userAgent, 'HubMarketApp-dev/1.0.0 (Flutter)');
        expect(
          AppConfig.forVersion(null).userAgent,
          AppConfig.current.userAgent,
        );
        expect(config.flavor, AppConfig.current.flavor);
        expect(config.graphqlEndpoint, AppConfig.current.graphqlEndpoint);
        expect(
          config.provisionalStoreCodes,
          AppConfig.current.provisionalStoreCodes,
        );
        expect(config.currency, AppConfig.current.currency);
        expect(config.algoliaAppId, AppConfig.current.algoliaAppId);
        expect(config.algoliaSearchKey, AppConfig.current.algoliaSearchKey);
        expect(config.algoliaIndexPrefix, AppConfig.current.algoliaIndexPrefix);
        expect(
          config.algoliaSortReplicas,
          AppConfig.current.algoliaSortReplicas,
        );
        expect(config.defaultLocale, AppConfig.current.defaultLocale);
        expect(config.bootstrapStoreCode, AppConfig.current.bootstrapStoreCode);
      },
    );
  });
}
