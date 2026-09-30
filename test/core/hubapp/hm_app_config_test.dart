import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';

import 'hubapp_fixtures.dart';

void main() {
  group('HmAppConfig.fromJson', () {
    test('reads every section of the contract', () {
      final config = HmAppConfig.fromJson(
        hmAppConfigJson(
          algolia: {
            'application_id': 'HL67ED06DQ',
            'search_api_key': 'secured',
            'valid_until': 1790756245,
            'index_prefix': 'hubmarket_',
            'product_index': 'hubmarket_en_products',
            'category_index': 'hubmarket_en_categories',
            'page_index': 'hubmarket_en_pages',
          },
        ),
      );

      expect(config.storeCode, 'en');
      expect(config.locale, 'en_US');
      expect(config.search.hint, 'Search Hub Market');
      // Blank terms dropped, admin order kept.
      expect(config.search.trendingTerms, ['iphone', 'abaya', 'rice']);
      expect(config.algolia!.productIndex, 'hubmarket_en_products');
      expect(
        config.algolia!.validUntil,
        DateTime.fromMillisecondsSinceEpoch(1790756245000, isUtc: true),
      );
      // wa.me derived from the number when the url is missing.
      expect(config.contact.whatsappUrl, 'https://wa.me/971501234567');
      expect(config.contact.phone, '+97145550000');
      expect(config.contact.hours, 'Daily 9 am – 11 pm');
      // An unknown platform row is dropped.
      expect(config.versions.map((v) => v.platform), [HmPlatform.android]);
      expect(config.maintenance.enabled, isFalse);
      expect(config.flag('returns'), isTrue);
      expect(config.flag('store_credit'), isFalse);
      expect(config.flag('push'), isNull);
      expect(config.features.keys, isNot(contains('')));
    });

    test('missing sections fall back to empty, never throw', () {
      final config = HmAppConfig.fromJson({'store_code': 'ar'});

      expect(config.search.hint, isNull);
      expect(config.search.trendingTerms, isEmpty);
      expect(config.algolia, isNull);
      expect(config.contact.isEmpty, isTrue);
      expect(config.versions, isEmpty);
      expect(config.maintenance.enabled, isFalse);
      expect(config.features, isEmpty);
    });

    test('capabilities: the satellites listed, none on an older server', () {
      final listed = HmAppConfig.fromJson(
        hmAppConfigJson(capabilities: ['account', ' ', 'vendors']),
      );
      expect(listed.capabilities, {'account', 'vendors'});
      expect(listed.hasCapability(HubAppCapability.vendors), isTrue);
      expect(listed.hasCapability(HubAppCapability.bundle), isFalse);

      final none = HmAppConfig.fromJson(hmAppConfigJson(capabilities: []));
      expect(none.capabilities, isEmpty);
      expect(none.hasCapability(HubAppCapability.vendors), isFalse);

      // A server from before the list: unknown, not "none".
      final older = HmAppConfig.fromJson(hmAppConfigJson());
      expect(older.capabilities, isNull);
      expect(older.hasCapability(HubAppCapability.vendors), isFalse);
    });

    test('an Algolia block without its key is no Algolia at all', () {
      final config = HmAppConfig.fromJson(
        hmAppConfigJson(
          algolia: {'application_id': 'HL67ED06DQ', 'product_index': 'x'},
        ),
      );
      expect(config.algolia, isNull);
    });

    test('maintenance reads its message and a positive wait only', () {
      final on = HmAppConfig.fromJson(hmAppConfigJson(maintenance: true));
      expect(on.maintenance.enabled, isTrue);
      expect(on.maintenance.message, 'Back soon — stocktaking.');
      expect(on.maintenance.retryAfterMinutes, 30);
      expect(
        HmMaintenance.fromJson({'enabled': true, 'retry_after_minutes': 0})
            .retryAfterMinutes,
        isNull,
      );
    });

    test('no store_code is not an hmAppConfig', () {
      expect(() => HmAppConfig.fromJson({}), throwsFormatException);
    });
  });

  group('versions', () {
    test('compareVersions reads major.minor.patch, ignoring suffixes', () {
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.2', '1.10.0'), lessThan(0));
      expect(compareVersions('2.0.0+7', '1.9.9'), greaterThan(0));
      expect(compareVersions('1.0.0-beta', '1.0.0'), 0);
      expect(compareVersions('v1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions(null, '1.0.0'), isNull);
      expect(compareVersions('1.0.0', 'soon'), isNull);
    });

    test('a build below min_version must update; unreadable never locks', () {
      final policy = HmAppConfig.fromJson(
        hmAppConfigJson(minVersion: '1.1.0'),
      ).versionFor(HmPlatform.android)!;
      expect(policy.requiresUpdate('1.0.0'), isTrue);
      expect(policy.requiresUpdate('1.1.0'), isFalse);
      expect(policy.requiresUpdate(null), isFalse);
      expect(policy.hasUpdate('1.1.0'), isTrue);
      expect(policy.hasUpdate('1.2.0'), isFalse);
      expect(
        const HmVersionPolicy(platform: HmPlatform.ios).requiresUpdate('0.0.1'),
        isFalse,
      );
    });
  });

  group('shared contract types', () {
    test('HmLink: every type, unknown values kept routable by url', () {
      final link = HmLink.fromJson({
        'type': 'CATEGORY',
        'url': 'https://hub-market.magento2.click/en/clothes.html',
        'path': 'clothes.html',
        'uid': 'MTQw',
        'code': null,
      })!;
      expect(link.type, HmLinkType.category);
      expect(link.uid, 'MTQw');
      expect(link.code, isNull);
      for (final type in HmLinkType.values.where((t) => t != HmLinkType.unknown)) {
        expect(HmLinkType.parse(type.wire), type);
      }
      expect(
        HmLink.fromJson({'type': 'OFFERS', 'url': 'https://x.example/a'})!.type,
        HmLinkType.unknown,
      );
      expect(HmLink.fromJson(null), isNull);
    });

    test('HmSellerSummary and HmStoreCard', () {
      final seller = HmSellerSummary.fromJson({
        'code': null,
        'vendor_entity_id': null,
        'name': 'Hub Market',
        'logo_url': null,
        'rating': null,
        'review_count': 0,
        'product_count': 120,
        'is_marketplace': true,
        'link': null,
      })!;
      expect(seller.isMarketplace, isTrue);
      expect(seller.code, isNull);
      expect(seller.productCount, 120);

      final card = HmStoreCard.fromJson({
        'code': 'loly',
        'vendor_entity_id': 12,
        'name': 'loly store',
        'logo_url': 'http://hub-market.magento2.click/media/ves_vendors/logo/l.png',
        'rating': 4.8,
        'review_count': 12,
        'product_count': 43,
        'dispatch_time': {'code': 'next_day', 'label': 'Next day', 'source': 'DECLARED'},
        'is_featured': true,
        'joined_at': '2026-05-01T08:00:00Z',
        'link': {'type': 'STORE', 'url': 'https://hub-market.magento2.click/en/shop/loly', 'code': 'loly'},
      })!;
      expect(card.logoUrl, startsWith('https://'));
      expect(card.dispatchTime!.source, HmDispatchSource.declared);
      expect(card.joinedAt, DateTime.utc(2026, 5, 1, 8));
      expect(card.link.type, HmLinkType.store);
      expect(HmStoreCard.fromJson({'code': 'x', 'name': 'X'}), isNull);
    });
  });
}
