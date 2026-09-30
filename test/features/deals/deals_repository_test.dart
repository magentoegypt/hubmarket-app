import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/deals/data/deals_repository.dart';
import 'package:hubmarket_app/features/deals/domain/deals.dart';

import '../../support/hubapp_fakes.dart';

Map<String, dynamic> _deals({bool withChips = true}) => {
  'hmDeals': {
    '__typename': 'HmProductPage',
    'total_count': 2,
    'countdown_ends_at': '2026-10-01T23:59:59+03:00',
    'page_info': {
      '__typename': 'SearchResultPageInfo',
      'current_page': 1,
      'page_size': 20,
      'total_pages': 1,
    },
    if (withChips)
      'categories': [
        {'__typename': 'HmCategoryCount', 'id': 3, 'uid': 'Mw==', 'name': 'Grocery', 'count': 7},
        {'__typename': 'HmCategoryCount', 'id': 5, 'uid': 'NQ==', 'name': 'Furniture', 'count': 4},
      ],
    'items': [
      {
        // The fragment's own type: this cache has no possible-types map to
        // match an interface fragment against a concrete type.
        '__typename': 'ProductInterface',
        'sku': 'RICE',
        'name': 'Egyptian Rice 1 kg',
        'url_key': 'egyptian-rice',
        'stock_status': 'IN_STOCK',
        'new_from_date': null,
        'new_to_date': null,
        'rating_summary': 90,
        'review_count': 3,
        'image': {'__typename': 'ProductImage', 'url': 'https://hub-market.magento2.click/media/rice.jpg'},
        'price_range': {
          '__typename': 'PriceRange',
          'minimum_price': {
            '__typename': 'ProductPrice',
            'regular_price': {'__typename': 'Money', 'value': 35, 'currency': 'AED'},
            'final_price': {'__typename': 'Money', 'value': 25, 'currency': 'AED'},
          },
        },
      },
    ],
  },
};

void main() {
  test('filters as scalar variables, the sort inline, no Hm-typed variable', () async {
    final log = <Request>[];
    final repository = DealsRepository(
      FakeHubAppClient({'HmDeals': _deals()}, log: log),
    );

    final page = await repository.fetchDeals(
      pageSize: 20,
      filters: const DealsFilters(
        categoryId: 5,
        minDiscount: 30,
        sort: DealsSort.endingSoon,
      ),
    );

    final request = log.single;
    expect(request.variables, {
      'pageSize': 20,
      'currentPage': 1,
      'categoryId': 5,
      'minDiscount': 30,
    });
    expect(
      DealsRepository.dealsDocument(DealsSort.endingSoon),
      allOf(contains('sort: ENDING_SOON'), isNot(contains('HmDealSort'))),
    );
    expect(page.filtered, isTrue);
    expect(page.totalCount, 2);
    expect(page.items.single.name, 'Egyptian Rice 1 kg');
    expect(page.categories.map((c) => (c.id, c.name, c.count)), [
      (3, 'Grocery', 7),
      (5, 'Furniture', 4),
    ]);
    expect(page.countdownEndsAt, isNotNull);
  });

  test('every sort is a value of HmDealSort', () {
    expect(DealsSort.values.map((s) => s.wire), [
      'DISCOUNT',
      'PRICE_ASC',
      'PRICE_DESC',
      'ENDING_SOON',
      'NEWEST',
    ]);
  });

  test('a HubApp older than the filters: the plain ranking, flagged', () async {
    final log = <Request>[];
    final repository = DealsRepository(
      FakeHubAppClient({
        'HmDeals': Response(
          errors: const [
            GraphQLError(
              message:
                  'Unknown argument "category_id" on field "hmDeals" of type "Query".',
            ),
          ],
          response: const <String, dynamic>{},
        ),
        'HmDealsP2': _deals(withChips: false),
      }, log: log),
    );

    final page = await repository.fetchDeals(
      filters: const DealsFilters(minDiscount: 20),
    );

    expect(log.map(operationNameOf), ['HmDeals', 'HmDealsP2']);
    expect(log.last.variables, {'pageSize': 20, 'currentPage': 1});
    expect(page.filtered, isFalse);
    expect(page.categories, isEmpty);
    expect(page.items, hasLength(1));
  });

  test('no hmDeals at all is HubAppMissing, as before', () async {
    final repository = DealsRepository(
      FakeHubAppClient({'HmDeals': hubAppMissingResponse('hmDeals')}),
    );

    await expectLater(repository.fetchDeals(), throwsA(isA<HubAppMissing>()));
  });
}
