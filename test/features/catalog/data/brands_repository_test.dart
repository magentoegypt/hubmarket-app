import 'package:flutter_test/flutter_test.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/data/brands_repository.dart';

import '../../../support/hubapp_fakes.dart';

Map<String, dynamic> _brand(
  int id,
  String name, {
  int? products,
  int? sellers,
}) => {
  '__typename': 'HmBrand',
  'id': id,
  'option_id': 200 + id,
  'name': name,
  'url_key': name.toLowerCase(),
  'logo_url': 'https://hub-market.magento2.click/media/mgs_brand/$id.png',
  'image_url': null,
  'is_featured': id == 1,
  'link': {
    '__typename': 'HmLink',
    'type': 'BRAND',
    'url': 'https://hub-market.magento2.click/en/brand/${name.toLowerCase()}.html',
    'path': null,
    'uid': null,
    'code': name.toLowerCase(),
  },
  'product_count': ?products,
  'seller_count': ?sellers,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'hmBrands': {
    '__typename': 'HmBrandPage',
    'total_count': items.length,
    'page_info': {'current_page': 1, 'page_size': 200, 'total_pages': 1},
    'items': items,
  },
};

void main() {
  test('brands with the counts hmBrands makes, in admin order', () async {
    final log = <Request>[];
    final repository = BrandsRepository(
      FakeHubAppClient({
        'HmBrands': _page([
          _brand(1, 'Samsung', products: 12, sellers: 2),
          _brand(2, 'Kodak', products: 0, sellers: 0),
        ]),
      }, log: log),
    );

    final brands = await repository.fetchBrands();

    expect(brands.map((b) => b.title), ['Samsung', 'Kodak']);
    expect(brands.first.productCount, 12);
    expect(brands.first.sellerCount, 2);
    expect(brands.first.optionId, 201);
    expect(brands.first.isFeatured, isTrue);
    expect(brands.last.productCount, 0);
    // One request: counts come with the brands, no facet or product scan.
    expect(log, hasLength(1));
    expect(log.single.variables, {'pageSize': 200, 'currentPage': 1});
  });

  test('a HubApp older than the counts: the brands without them', () async {
    final log = <Request>[];
    final repository = BrandsRepository(
      FakeHubAppClient({
        'HmBrands': hubAppMissingResponse('product_count', type: 'HmBrand'),
        'HmBrandsP2': _page([_brand(1, 'Samsung')]),
      }, log: log),
    );

    final brands = await repository.fetchBrands();

    expect(brands.single.title, 'Samsung');
    expect(brands.single.productCount, isNull);
    expect(brands.single.sellerCount, isNull);
    expect(log.map(operationNameOf), ['HmBrands', 'HmBrandsP2']);
  });

  test('no HubApp at all is still HubAppMissing', () async {
    final repository = BrandsRepository(
      FakeHubAppClient({'HmBrands': hubAppMissingResponse('hmBrands')}),
    );

    await expectLater(repository.fetchBrands(), throwsA(isA<HubAppMissing>()));
  });
}
