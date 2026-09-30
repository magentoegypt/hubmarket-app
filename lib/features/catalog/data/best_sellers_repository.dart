import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../domain/product.dart';
import 'product_mapper.dart';

/// Best sellers by units ordered (`hmBestSellers`, the Hub Market App
/// backend) — the no-results page's "Popular right now" (Figma S2). A public
/// read over the GET client; throws [HubAppMissing] when the server has no
/// such field, a `Failure` for anything else.
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

  Future<List<Product>> fetch({int pageSize = 10}) async {
    final data = await runHubAppQuery(
      _client,
      query,
      variables: <String, dynamic>{
        'pageSize': pageSize.clamp(1, maxPageSize),
        'currentPage': 1,
      },
    );
    final page = data['hmBestSellers'];
    final items = page is Map<String, dynamic> ? page['items'] : null;
    return [
      for (final item in items is List ? items : const <Object?>[])
        if (item is Map<String, dynamic>) productFromJson(item),
    ].where((p) => p.urlKey.isNotEmpty).toList(growable: false);
  }
}

final bestSellersRepositoryProvider = Provider<BestSellersRepository>(
  (ref) => BestSellersRepository(ref.watch(publicGraphqlClientProvider)),
);
