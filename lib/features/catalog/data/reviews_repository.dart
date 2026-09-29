import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/util/media.dart';
import '../domain/product_detail.dart';
import '../domain/review_pages.dart';

/// Core Magento review reads: a product's published reviews, paged, and the
/// signed-in customer's own reviews.
abstract final class ReviewQueries {
  static const String _reviewFields = r'''
fragment ReviewFields on ProductReview {
  nickname
  summary
  text
  average_rating
  created_at
}
''';

  static String _withReviewFields(String operation) =>
      '$operation\n$_reviewFields';

  /// `ProductReviews` has no total count — `review_count` on the product is
  /// the total; `page_info.total_pages` drives paging.
  static final String productReviews = _withReviewFields(r'''
query ProductReviews($urlKey: String!, $pageSize: Int!, $currentPage: Int!) {
  products(filter: { url_key: { eq: $urlKey } }, pageSize: 1) {
    items {
      sku
      name
      url_key
      rating_summary
      review_count
      reviews(pageSize: $pageSize, currentPage: $currentPage) {
        items { ...ReviewFields }
        page_info { current_page page_size total_pages }
      }
    }
  }
}''');

  static final String customerReviews = _withReviewFields(r'''
query CustomerReviews($pageSize: Int!, $currentPage: Int!) {
  customer {
    reviews(pageSize: $pageSize, currentPage: $currentPage) {
      items {
        ...ReviewFields
        product {
          sku
          name
          url_key
          small_image { url }
        }
      }
      page_info { current_page page_size total_pages }
    }
  }
}''');
}

class ReviewsRepository {
  ReviewsRepository(this._client);

  final GraphQLClient _client;

  /// Page [currentPage] of the product's published reviews, or null when no
  /// product has [urlKey] in the active store view.
  Future<ProductReviewsPage?> fetchProductReviews(
    String urlKey, {
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final data = await _query(ReviewQueries.productReviews, {
      'urlKey': urlKey,
      'pageSize': pageSize,
      'currentPage': currentPage,
    });
    final items =
        (data['products'] as Map<String, dynamic>?)?['items']
            as List<dynamic>?;
    final product = (items == null || items.isEmpty) ? null : items.first;
    if (product is! Map<String, dynamic>) return null;
    final reviews = product['reviews'] as Map<String, dynamic>?;
    final pageInfo = reviews?['page_info'] as Map<String, dynamic>?;
    return ProductReviewsPage(
      sku: (product['sku'] as String?) ?? '',
      name: (product['name'] as String?) ?? '',
      urlKey: (product['url_key'] as String?) ?? urlKey,
      ratingSummary: (product['rating_summary'] as num?)?.round() ?? 0,
      reviewCount: (product['review_count'] as num?)?.toInt() ?? 0,
      reviews: _reviews(reviews?['items']).map(ProductReview.fromJson).toList(),
      currentPage: (pageInfo?['current_page'] as num?)?.toInt() ?? currentPage,
      totalPages: (pageInfo?['total_pages'] as num?)?.toInt() ?? 0,
    );
  }

  /// Page [currentPage] of the signed-in customer's reviews, newest first.
  Future<CustomerReviewsPage> fetchCustomerReviews({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final data = await _query(ReviewQueries.customerReviews, {
      'pageSize': pageSize,
      'currentPage': currentPage,
    });
    final reviews =
        (data['customer'] as Map<String, dynamic>?)?['reviews']
            as Map<String, dynamic>?;
    final pageInfo = reviews?['page_info'] as Map<String, dynamic>?;
    return CustomerReviewsPage(
      items: [
        for (final json in _reviews(reviews?['items']))
          CustomerReview(
            review: ProductReview.fromJson(json),
            productName: (_product(json)['name'] as String?) ?? '',
            productSku: _product(json)['sku'] as String?,
            productUrlKey: _product(json)['url_key'] as String?,
            productImageUrl: httpsMediaUrl(
              (_product(json)['small_image'] as Map<String, dynamic>?)?['url']
                  as String?,
            ),
          ),
      ],
      currentPage: (pageInfo?['current_page'] as num?)?.toInt() ?? currentPage,
      totalPages: (pageInfo?['total_pages'] as num?)?.toInt() ?? 0,
    );
  }

  Iterable<Map<String, dynamic>> _reviews(Object? items) =>
      ((items as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>();

  Map<String, dynamic> _product(Map<String, dynamic> review) =>
      (review['product'] as Map<String, dynamic>?) ?? const {};

  Future<Map<String, dynamic>> _query(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(document),
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
}

final reviewsRepositoryProvider = Provider<ReviewsRepository>(
  (ref) => ReviewsRepository(ref.watch(graphqlClientProvider)),
);
