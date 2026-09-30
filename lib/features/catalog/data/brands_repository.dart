import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../domain/brand.dart';

/// MGS brands through the Hub Market App API (`hmBrands`), with how many
/// products each one's page lists and from how many sellers — counted by the
/// backend, through the storefront's own visibility gate. Public reads over
/// the GET client.
class BrandsRepository {
  BrandsRepository(this._client);

  final GraphQLClient _client;

  static const String _brandsDocument = r'''
query HmBrands($pageSize: Int!, $currentPage: Int!) {
  hmBrands(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page page_size total_pages }
    items { ...HmBrandFields product_count seller_count }
  }
}
''';

  /// [_brandsDocument] without the counts, for a HubApp deployed before them.
  static const String _brandsDocumentP2 = r'''
query HmBrandsP2($pageSize: Int!, $currentPage: Int!) {
  hmBrands(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page page_size total_pages }
    items { ...HmBrandFields }
  }
}
''';

  /// `...HmBrandFields` on `HmBrand` (spreads `HmLinkFields`). The Home's
  /// brand strip spreads it too, so it carries no counts: the Home needs none.
  static const String brandFields =
      r'''fragment HmBrandFields on HmBrand{id option_id name url_key logo_url image_url is_featured link{...HmLinkFields}}''';

  /// Every enabled brand of this store view, in admin order, with their
  /// counts. Throws [HubAppMissing] without the Hub Market App API; a HubApp
  /// older than the counts gives the brands without them.
  Future<List<Brand>> fetchBrands() async {
    try {
      return await _fetchAll(_brandsDocument);
    } on HubAppMissing catch (missing) {
      // "Cannot query field "product_count" on type "HmBrand"": HubApp is
      // there, only older.
      if (missing.message.contains('"hmBrands"')) rethrow;
      return _fetchAll(_brandsDocumentP2);
    }
  }

  Future<List<Brand>> _fetchAll(String document) async {
    final brands = <Brand>[];
    for (var page = 1; page <= 5; page++) {
      final data = await runHubAppQuery(
        _client,
        document + brandFields + HmFragments.link,
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
  int? count(String key) {
    final value = hmInt(json[key]);
    return value == null || value < 0 ? null : value;
  }

  return Brand(
    brandId: hmInt(json['id']) ?? 0,
    title: name,
    urlKey: urlKey,
    url: link?.url ?? '',
    imageUrl: hmImageUrl(json['logo_url']) ?? hmImageUrl(json['image_url']) ?? '',
    optionId: hmInt(json['option_id']),
    position: position,
    isFeatured: json['is_featured'] == true,
    productCount: count('product_count'),
    sellerCount: count('seller_count'),
  );
}
