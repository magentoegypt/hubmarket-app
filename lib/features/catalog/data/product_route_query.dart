import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../domain/product_detail.dart';
import 'catalog_queries.dart';
import 'product_mapper.dart';

/// The product page's own query ([CatalogQueries.productDetail]) asked by URL
/// through `route`, for the products product search leaves out: other
/// sellers' offers (Vnecoms "select and sell" copies), opened from "Sold by N
/// other sellers".
///
/// Derived from the page's query rather than written out again, so the two
/// can never drift: the same selection, under
/// `route(url: $url) { ... on ProductInterface { … } }` instead of
/// `products(filter: {url_key}) { items { … } }`. The response's `route` is
/// then read exactly like `products.items[0]`.
final String productDetailByRoute = productDetailByRouteOf(
  CatalogQueries.productDetail,
);

// Single-quoted on purpose: these are fragments of a document, not documents,
// and tool/validate_ops.py only reads triple-quoted strings.
const String _byUrlKey =
    'query ProductDetail(\$urlKey: String!) {\n'
    '  products(filter: { url_key: { eq: \$urlKey } }, pageSize: 1) {\n'
    '    items {';

const String _byUrl =
    'query ProductDetailByRoute(\$url: String!) {\n'
    '  route(url: \$url) {\n'
    '    ... on ProductInterface {';

/// [productDetail] with its `products(filter: {url_key})` head swapped for
/// `route(url:)`. Throws [StateError] when the head is not the one expected —
/// a changed product query must be looked at here too (a unit test runs this).
String productDetailByRouteOf(String productDetail) {
  final text = productDetail.replaceAll('\r\n', '\n');
  if (!text.contains(_byUrlKey)) {
    throw StateError('ProductDetail no longer opens with products(url_key)');
  }
  return text.replaceFirst(_byUrlKey, _byUrl);
}

/// Reads a product page by its URL ([productDetailByRoute]), with the same
/// client and the same mapping as the page's own read.
class ProductRouteRepository {
  ProductRouteRepository(this._client);

  final GraphQLClient _client;

  /// The product at the store-relative [url]; null when [url] is not a
  /// product. Throws a [Failure] when the read fails.
  Future<ProductDetail?> fetchDetail(String url) async {
    final QueryResult result;
    try {
      result = await _client.query(
        QueryOptions(
          document: gql(productDetailByRoute),
          variables: <String, dynamic>{'url': url},
          // `... on ProductInterface`: the client's cache has no
          // possibleTypes, and reading the answer back through it would drop
          // every product field. The response is used as sent.
          fetchPolicy: FetchPolicy.noCache,
        ),
      );
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
    if (result.hasException) throw mapOperationException(result.exception!);
    final page = result.data?['route'];
    // A CMS page or a category answers without the product's fields.
    if (page is! Map<String, dynamic> || page['sku'] == null) return null;
    return productDetailFromJson(page);
  }
}

final productRouteRepositoryProvider = Provider<ProductRouteRepository>(
  (ref) => ProductRouteRepository(ref.watch(graphqlClientProvider)),
);
