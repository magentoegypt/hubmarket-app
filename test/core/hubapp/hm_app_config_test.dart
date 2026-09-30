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

    test('shipping: the free-shipping threshold, or none', () {
      final config = HmAppConfig.fromJson(
        hmAppConfigJson(
          shipping: {
            'free_over': {'value': 50, 'currency': 'AED'},
          },
        ),
      );
      expect(config.shipping.freeOver, 50.0);
      expect(config.shipping.currency, 'AED');

      // No rule: null; an older backend: no shipping at all.
      expect(
        HmAppConfig.fromJson(
          hmAppConfigJson(shipping: {'free_over': null}),
        ).shipping.freeOver,
        isNull,
      );
      expect(HmAppConfig.fromJson(hmAppConfigJson()).shipping.freeOver, isNull);
      expect(
        HmShippingConfig.fromJson({
          'free_over': {'value': -1, 'currency': 'AED'},
        }).freeOver,
        isNull,
      );
    });

    test('algolia: the storefront layout when the backend sends it', () {
      final config = HmAppConfig.fromJson(
        hmAppConfigJson(
          algolia: {
            'application_id': 'HL67ED06DQ',
            'search_api_key': 'secured',
            'index_prefix': 'hubmarket_',
            'product_index': 'hubmarket_ar_products',
            'category_index': 'hubmarket_ar_categories',
            'page_index': 'hubmarket_ar_pages',
            'facets': [
              {'attribute': 'price', 'type': 'slider', 'label': 'السعر'},
              {'attribute': 'mgs_brand', 'type': 'disjunctive', 'label': null},
              {'attribute': '', 'type': 'disjunctive'},
            ],
            'sorts': [
              {
                'index': 'hubmarket_ar_products_price_default_asc',
                'attribute': 'price',
                'direction': 'ASC',
                'label': 'الأقل سعراً',
              },
              {
                'index': 'hubmarket_ar_products_created_at_desc',
                'attribute': 'created_at',
                'direction': 'DESC',
                'label': 'الأحدث أولاً',
              },
              {'index': 'x', 'attribute': 'y', 'direction': 'SIDEWAYS'},
            ],
            'suggestion_index': 'hubmarket_ar_suggestions',
            'suggestion_count': 5,
            'currency_code': 'AED',
            'price_group': 'default',
            'max_values_per_facet': 10,
            'product_suggestions': 8,
            'category_suggestions': 2,
            'page_suggestions': 2,
            'category_separator': ' /// ',
            'categories_outside_menu': false,
          },
        ),
      );

      final layout = config.algolia!.layout!;
      expect(layout.facets.map((f) => f.attribute), ['price', 'mgs_brand']);
      expect(layout.facets.first.label, 'السعر');
      expect(layout.facets.last.label, '');
      expect(layout.sorts, hasLength(2));
      expect(layout.sorts.first.descending, isFalse);
      expect(layout.sorts.last.descending, isTrue);
      expect(layout.sorts.last.label, 'الأحدث أولاً');
      expect(layout.suggestionIndex, 'hubmarket_ar_suggestions');
      expect(layout.suggestionCount, 5);
      expect(layout.currencyCode, 'AED');
      expect(layout.priceGroup, 'default');
      expect(layout.maxValuesPerFacet, 10);
      expect(layout.productSuggestions, 8);
      expect(layout.pageSuggestions, 2);
      // As indexed, spaces kept.
      expect(layout.categorySeparator, ' /// ');
    });

    test('algolia: no layout from a backend older than it', () {
      final config = HmAppConfig.fromJson(
        hmAppConfigJson(
          algolia: {
            'application_id': 'HL67ED06DQ',
            'search_api_key': 'secured',
            'product_index': 'hubmarket_en_products',
          },
        ),
      );
      expect(config.algolia, isNotNull);
      expect(config.algolia!.layout, isNull);
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
