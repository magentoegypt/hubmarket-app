import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../catalog/data/product_mapper.dart';
import '../../catalog/domain/money.dart';
import '../domain/deals.dart';

/// The Hub Market App's catalogue lists: today's deals (`hmDeals`) and bundle
/// deals (`hmBundleDeals`). Public reads over the GET client; throws
/// [HubAppMissing] when the server has no such fields, a `Failure` otherwise.
class DealsRepository {
  DealsRepository(this._client);

  final GraphQLClient _client;

  /// The most a page may ask for (the contract caps `pageSize` at 50).
  static const int maxPageSize = 50;

  static const String _dealsDocument = r'''
query HmDeals($pageSize: Int!, $currentPage: Int!) {
  hmDeals(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    countdown_ends_at
    page_info { current_page page_size total_pages }
    items { ...HmCardProduct categories { uid name level include_in_menu } }
  }
}
''';

  static const String _bundlesDocument = r'''
query HmBundleDeals($categoryId: Int, $pageSize: Int!, $currentPage: Int!) {
  hmBundleDeals(category_id: $categoryId, pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    max_discount_percent
    seller_count
    categories { id uid name count }
    page_info { current_page page_size total_pages }
    items { ...HmBundleCard }
  }
}
''';

  Future<DealsPage> fetchDeals({int pageSize = 20, int currentPage = 1}) async {
    final data = await runHubAppQuery(
      _client,
      _dealsDocument + DealsFragments.cardProduct,
      variables: {
        'pageSize': pageSize.clamp(1, maxPageSize),
        'currentPage': currentPage,
      },
    );
    return dealsPageFromJson(data['hmDeals']);
  }

  Future<BundleDealPage> fetchBundleDeals({
    int? categoryId,
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final data = await runHubAppQuery(
      _client,
      _bundlesDocument + DealsFragments.bundleCard + HmFragments.link,
      variables: {
        'categoryId': categoryId,
        'pageSize': pageSize.clamp(1, maxPageSize),
        'currentPage': currentPage,
      },
    );
    return bundleDealPageFromJson(data['hmBundleDeals']);
  }
}

final dealsRepositoryProvider = Provider<DealsRepository>(
  (ref) => DealsRepository(ref.watch(publicGraphqlClientProvider)),
);

/// GraphQL fragments of the deal cards, shared with the Home document.
abstract final class DealsFragments {
  /// `...HmCardProduct` — a listing card (the catalogue `products` card
  /// fields) plus who sells it.
  static const String cardProduct =
      r'''fragment HmCardProduct on ProductInterface{sku name url_key stock_status new_from_date new_to_date image{url} price_range{minimum_price{regular_price{value currency} final_price{value currency}}} hm_seller{code name}}''';

  /// `...HmBundleCard` on `HmBundleDeal` (spreads `HmLinkFields`).
  static const String bundleCard =
      r'''fragment HmBundleCard on HmBundleDeal{uid sku name url_key image_url seller{code name link{...HmLinkFields}} description is_kit item_count thumbnails more_thumbnails price{value currency} price_is_from regular_total{value currency} saving{value currency} discount_percent rating_percent review_count category_ids}''';
}

/// `hmDeals` → [DealsPage]; empty for anything that isn't one.
DealsPage dealsPageFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return DealsPage.empty;
  final items = [
    for (final item in json['items'] is List ? json['items'] as List : const [])
      if (item is Map<String, dynamic>) productFromJson(item),
  ].where((p) => p.urlKey.isNotEmpty).toList(growable: false);
  return DealsPage(
    items: items,
    totalCount: hmInt(json['total_count']) ?? items.length,
    pageInfo: HmPageInfo.fromJson(json['page_info']),
    countdownEndsAt: hmDateTime(json['countdown_ends_at']),
  );
}

/// `hmBundleDeals` → [BundleDealPage]; empty for anything that isn't one.
BundleDealPage bundleDealPageFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return BundleDealPage.empty;
  return BundleDealPage(
    items: [
      for (final item in json['items'] is List ? json['items'] as List : const [])
        if (bundleDealFromJson(item) case final deal?) deal,
    ],
    categories: [
      for (final c in json['categories'] is List ? json['categories'] as List : const [])
        if (c is Map<String, dynamic>)
          if ((hmString(c['uid']), hmString(c['name'])) case (
            final uid?,
            final name?,
          ))
            DealCategory(
              id: hmInt(c['id']) ?? 0,
              uid: uid,
              name: name,
              count: hmInt(c['count']) ?? 0,
            ),
    ],
    maxDiscountPercent: hmInt(json['max_discount_percent']) ?? 0,
    sellerCount: hmInt(json['seller_count']) ?? 0,
    totalCount: hmInt(json['total_count']) ?? 0,
    pageInfo: HmPageInfo.fromJson(json['page_info']),
  );
}

/// One `HmBundleDeal`; null without a name, url_key or price.
BundleDeal? bundleDealFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return null;
  final name = hmString(json['name']);
  final urlKey = hmString(json['url_key']);
  final price = moneyFromJson(json['price'] as Map<String, dynamic>?);
  if (name == null || urlKey == null || price == null) return null;
  Money? money(String key) {
    final value = json[key];
    return value is Map<String, dynamic> ? moneyFromJson(value) : null;
  }

  return BundleDeal(
    uid: hmString(json['uid']) ?? '',
    sku: hmString(json['sku']) ?? '',
    name: name,
    urlKey: urlKey,
    price: price,
    imageUrl: hmImageUrl(json['image_url']),
    seller: HmSellerSummary.fromJson(json['seller']),
    description: hmString(json['description']),
    isKit: json['is_kit'] != false,
    itemCount: hmInt(json['item_count']) ?? 0,
    thumbnails: [
      for (final t in hmStrings(json['thumbnails']))
        if (hmImageUrl(t) case final url?) url,
    ],
    moreThumbnails: hmInt(json['more_thumbnails']) ?? 0,
    priceIsFrom: json['price_is_from'] == true,
    regularTotal: money('regular_total'),
    saving: money('saving'),
    discountPercent: hmInt(json['discount_percent']) ?? 0,
    ratingPercent: hmInt(json['rating_percent']),
    reviewCount: hmInt(json['review_count']) ?? 0,
    categoryIds: [
      for (final id in json['category_ids'] is List ? json['category_ids'] as List : const [])
        if (hmInt(id) case final value?) value,
    ],
  );
}
