import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../domain/product.dart';
import 'product_mapper.dart';

/// Best sellers by units ordered (`hmBestSellers`, the Hub Market App
/// backend) — the no-results page's "Popular right now" (Figma S2) and the
/// best-sellers page. A public read over the GET client; throws
/// [HubAppMissing] when the server has no such field, a `Failure` for
/// anything else.
class BestSellersRepository {
  BestSellersRepository(this._client);

  final GraphQLClient _client;

  /// The backend accepts 1–50 per page.
  static const int maxPageSize = 50;

  /// The listing card's fields, as the PLP asks for them.
  static const String query = r'''
query HmBestSellers($pageSize: Int, $currentPage: Int) {
  hmBestSellers(pageSize: $pageSize, currentPage: $currentPage) {
    total_count
    page_info { current_page page_size total_pages }
    items {
      sku
      name
      url_key
      stock_status
      new_from_date
      new_to_date
      rating_summary
      review_count
      image { url label }
      price_range {
        minimum_price {
          regular_price { value currency }
          final_price { value currency }
        }
      }
    }
  }
}
''';

  /// The top [pageSize] best sellers.
  Future<List<Product>> fetch({int pageSize = 10}) async =>
      (await fetchPage(pageSize: pageSize)).items;

  /// Page [currentPage] of the ranking, [pageSize] (1–50) a page. The backend
  /// ranks at most 200 products.
  Future<BestSellersPage> fetchPage({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final data = await runHubAppQuery(
      _client,
      query,
      variables: <String, dynamic>{
        'pageSize': pageSize.clamp(1, maxPageSize),
        'currentPage': currentPage < 1 ? 1 : currentPage,
      },
    );
    return bestSellersPageFromJson(data['hmBestSellers']);
  }
}

/// One page of `hmBestSellers`, in rank order.
@immutable
class BestSellersPage {
  const BestSellersPage({
    this.items = const <Product>[],
    this.totalCount = 0,
    this.pageInfo = const HmPageInfo(),
  });

  final List<Product> items;

  /// Ranked products available (the backend caps it at 200).
  final int totalCount;
  final HmPageInfo pageInfo;

  static const BestSellersPage empty = BestSellersPage();
}

/// `hmBestSellers` → [BestSellersPage]; empty for anything that isn't one.
/// Products without a url_key (nothing to open) are left out.
BestSellersPage bestSellersPageFromJson(Object? json) {
  if (json is! Map<String, dynamic>) return BestSellersPage.empty;
  final items = [
    for (final item in json['items'] is List ? json['items'] as List : const [])
      if (item is Map<String, dynamic>) productFromJson(item),
  ].where((p) => p.urlKey.isNotEmpty).toList(growable: false);
  return BestSellersPage(
    items: items,
    totalCount: hmInt(json['total_count']) ?? items.length,
    pageInfo: HmPageInfo.fromJson(json['page_info']),
  );
}

final bestSellersRepositoryProvider = Provider<BestSellersRepository>(
  (ref) => BestSellersRepository(ref.watch(publicGraphqlClientProvider)),
);
