import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../catalog/data/catalog_queries.dart';
import '../../catalog/data/catalog_repository.dart' show ProductSortField;
import '../../catalog/data/product_mapper.dart';
import '../../catalog/domain/aggregation.dart';
import '../../catalog/domain/product_page.dart';

/// One seller's products: core `products` narrowed by the `vendor_id` match
/// filter, with the listing's own search, attribute filters, price range,
/// sort and paging — the PLP's product document and card fields.
///
/// `vendor_id` is a match filter in the live `ProductAttributeFilterInput`,
/// so it is sent as `{match: "<id>", match_type: FULL}`. PARTIAL would also
/// match every id that merely contains the digits (12 in 112), and `eq`
/// fails validation.
///
/// A public read like the store page that leads to it, so it goes as GET
/// through `publicGraphqlClientProvider` and the HTTP cache can answer it —
/// guest prices, as the Home's product sections show.
class StoreProductsRepository {
  StoreProductsRepository(this._client);

  final GraphQLClient _client;

  /// Facets of the seller filter itself: pointless on one seller's page.
  static const Set<String> _sellerFacets = <String>{'vendor_id', 'VENDORID'};

  Future<ProductPage> fetchProducts({
    required int vendorEntityId,
    String? search,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final query = search?.trim() ?? '';
    final data = await _query(<String, dynamic>{
      'pageSize': pageSize,
      'currentPage': currentPage,
      if (query.isNotEmpty) 'search': query,
      'filter': storeProductsFilter(
        vendorEntityId: vendorEntityId,
        attributeFilters: attributeFilters,
        priceFrom: priceFrom,
        priceTo: priceTo,
      ),
      if (_sortInput(sort) case final sortInput?) 'sort': sortInput,
    });
    final products = data['products'];
    return products is Map<String, dynamic>
        ? _page(products)
        : ProductPage.empty;
  }

  Map<String, dynamic>? _sortInput(ProductSortField sort) => switch (sort) {
    ProductSortField.relevance => null,
    ProductSortField.priceAsc => const <String, dynamic>{'price': 'ASC'},
    ProductSortField.priceDesc => const <String, dynamic>{'price': 'DESC'},
    ProductSortField.nameAsc => const <String, dynamic>{'name': 'ASC'},
  };

  Future<Map<String, dynamic>> _query(Map<String, dynamic> variables) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(CatalogQueries.products),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }

  ProductPage _page(Map<String, dynamic> json) {
    final items = (json['items'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(productFromJson)
        .toList(growable: false);
    final pageInfo = json['page_info'] as Map<String, dynamic>?;
    return ProductPage(
      items: items,
      totalCount: (json['total_count'] as num?)?.toInt() ?? items.length,
      currentPage: (pageInfo?['current_page'] as num?)?.toInt() ?? 1,
      totalPages: (pageInfo?['total_pages'] as num?)?.toInt() ?? 1,
      aggregations: [
        for (final agg
            in (json['aggregations'] as List<dynamic>? ?? const <dynamic>[])
                .whereType<Map<String, dynamic>>())
          if (!_sellerFacets.contains(agg['attribute_code']))
            Aggregation(
              attributeCode: (agg['attribute_code'] as String?) ?? '',
              label: (agg['label'] as String?) ?? '',
              options: [
                for (final o
                    in (agg['options'] as List<dynamic>? ?? const <dynamic>[])
                        .whereType<Map<String, dynamic>>())
                  AggregationOption(
                    label: (o['label'] as String?) ?? '',
                    value: (o['value'] as String?) ?? '',
                    count: (o['count'] as num?)?.toInt() ?? 0,
                  ),
              ],
            ),
      ],
    );
  }
}

/// The `ProductAttributeFilterInput` of one seller's listing: the seller,
/// then the shopper's attribute filters (`in`) and price range.
Map<String, dynamic> storeProductsFilter({
  required int vendorEntityId,
  Map<String, Set<String>> attributeFilters = const {},
  double? priceFrom,
  double? priceTo,
}) => <String, dynamic>{
  'vendor_id': <String, dynamic>{
    'match': '$vendorEntityId',
    'match_type': 'FULL',
  },
  for (final MapEntry(key: code, value: values) in attributeFilters.entries)
    if (code != 'price' && values.isNotEmpty)
      code: <String, dynamic>{'in': values.toList()},
  if (priceFrom != null || priceTo != null)
    'price': <String, dynamic>{
      if (priceFrom != null) 'from': priceFrom.toStringAsFixed(2),
      if (priceTo != null) 'to': priceTo.toStringAsFixed(2),
    },
};

final storeProductsRepositoryProvider = Provider<StoreProductsRepository>(
  (ref) => StoreProductsRepository(ref.watch(publicGraphqlClientProvider)),
);
