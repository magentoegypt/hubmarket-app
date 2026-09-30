import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../domain/brand.dart';
import 'product_mapper.dart';

/// MGS brands through the Hub Market App API (`hmBrands`), and how many
/// catalogue products each one has (the `mgs_brand` facet of the whole
/// catalogue). Public reads over the GET client.
class BrandsRepository {
  BrandsRepository(this._client);

  final GraphQLClient _client;

  /// The root category every listed product sits under (CLAUDE.md §1).
  static const String rootCategoryUid = 'Mg==';

  static const String _brandsDocument = r'''
query HmBrands($pageSize: Int!, $currentPage: Int!) {
  hmBrands(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page page_size total_pages }
    items { ...HmBrandFields }
  }
}
''';

  /// `...HmBrandFields` on `HmBrand` (spreads `HmLinkFields`).
  static const String brandFields =
      r'''fragment HmBrandFields on HmBrand{id option_id name url_key logo_url image_url is_featured link{...HmLinkFields}}''';

  static const String _countsDocument = r'''
query BrandProductCounts($root: String!) {
  products(filter: { category_uid: { eq: $root } }, pageSize: 1) {
    aggregations { attribute_code options { value count } }
  }
}
''';

  static const String _sellersDocument = r'''
query BrandSellers($option: String!, $pageSize: Int!) {
  products(filter: { mgs_brand: { eq: $option } }, pageSize: $pageSize) {
    total_count
    items { hm_seller { code } }
  }
}
''';

  /// The most products [fetchSellerCount] reads to count sellers.
  static const int sellerScanLimit = 50;

  /// How many sellers carry brand [optionId] ("from 2 stores"): Hub Market
  /// itself counts as one. Null when the brand has more products than
  /// [sellerScanLimit] — the count would be a guess.
  Future<int?> fetchSellerCount(int optionId) async {
    final data = await runHubAppQuery(
      _client,
      _sellersDocument,
      variables: {'option': '$optionId', 'pageSize': sellerScanLimit},
    );
    final products = data['products'];
    if (products is! Map<String, dynamic>) return null;
    final items = products['items'] is List ? products['items'] as List : const [];
    final total = hmInt(products['total_count']) ?? items.length;
    if (total > items.length) return null;
    final sellers = <String>{
      for (final item in items)
        if (item is Map<String, dynamic>)
          hmString((item['hm_seller'] as Map<String, dynamic>?)?['code']) ??
              '',
    };
    return sellers.length;
  }

  /// Every enabled brand of this store view, in admin order. Throws
  /// [HubAppMissing] without the Hub Market App API.
  Future<List<Brand>> fetchBrands() async {
    final brands = <Brand>[];
    for (var page = 1; page <= 5; page++) {
      final data = await runHubAppQuery(
        _client,
        _brandsDocument + brandFields + HmFragments.link,
        variables: {'pageSize': 200, 'currentPage': page},
      );
      final json = data['hmBrands'];
      if (json is! Map<String, dynamic>) break;
      for (final item in json['items'] is List ? json['items'] as List : const []) {
        if (brandFromHmJson(item, position: brands.length) case final brand?) {
          brands.add(brand);
        }
      }
      if (!HmPageInfo.fromJson(json['page_info']).hasMore) break;
    }
    return List.unmodifiable(brands);
  }

  /// Catalogue products per brand option id (the `mgs_brand` facet); empty
  /// when the facet isn't there.
  Future<Map<int, int>> fetchProductCounts() async {
    final data = await runHubAppQuery(
      _client,
      _countsDocument,
      variables: const {'root': rootCategoryUid},
    );
    final aggregations =
        (data['products'] as Map<String, dynamic>?)?['aggregations'];
    for (final agg in aggregations is List ? aggregations : const []) {
      if (agg is! Map<String, dynamic>) continue;
      if (agg['attribute_code'] != kBrandAttributeCode) continue;
      return {
        for (final option in agg['options'] is List ? agg['options'] as List : const [])
          if (option is Map<String, dynamic>)
            if (hmInt(option['value']) case final id?)
              id: hmInt(option['count']) ?? 0,
      };
    }
    return const <int, int>{};
  }
}

final brandsRepositoryProvider = Provider<BrandsRepository>(
  (ref) => BrandsRepository(ref.watch(publicGraphqlClientProvider)),
);

/// One `HmBrand` as the app's [Brand]; null without a name or url_key.
Brand? brandFromHmJson(Object? json, {int position = 0}) {
  if (json is! Map<String, dynamic>) return null;
  final name = hmString(json['name']);
  final urlKey = hmString(json['url_key']);
  if (name == null || urlKey == null) return null;
  final link = HmLink.fromJson(json['link']);
  return Brand(
    brandId: hmInt(json['id']) ?? 0,
    title: name,
    urlKey: urlKey,
    url: link?.url ?? '',
    imageUrl: hmImageUrl(json['logo_url']) ?? hmImageUrl(json['image_url']) ?? '',
    optionId: hmInt(json['option_id']),
    position: position,
    isFeatured: json['is_featured'] == true,
  );
}
