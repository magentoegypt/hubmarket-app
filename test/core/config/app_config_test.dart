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
      expect(config.graphqlEndpoint, 'https://hub-market.magento2.click/graphql');
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
  });
}
