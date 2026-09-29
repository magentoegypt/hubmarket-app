import 'product_detail.dart';

/// One page of a product's published reviews, with the product's totals.
class ProductReviewsPage {
  const ProductReviewsPage({
    required this.sku,
    required this.name,
    required this.urlKey,
    required this.ratingSummary,
    required this.reviewCount,
    required this.reviews,
    required this.currentPage,
    required this.totalPages,
  });

  final String sku;
  final String name;
  final String urlKey;

  /// 0–100 (Magento `rating_summary`), over all published reviews.
  final int ratingSummary;

  /// All published reviews in this store view (`review_count`).
  final int reviewCount;
  final List<ProductReview> reviews;
  final int currentPage;
  final int totalPages;
}

/// A review the signed-in customer wrote, with the product it is about.
///
/// Core `customer { reviews }` returns the customer's reviews whatever their
/// moderation status, but `ProductReview` has no status field — so the app
/// cannot tell a pending review from a published one and shows neither badge.
class CustomerReview {
  const CustomerReview({
    required this.review,
    required this.productName,
    this.productSku,
    this.productUrlKey,
    this.productImageUrl,
  });

  final ProductReview review;
  final String productName;
  final String? productSku;
  final String? productUrlKey;
  final String? productImageUrl;
}

class CustomerReviewsPage {
  const CustomerReviewsPage({
    required this.items,
    required this.currentPage,
    required this.totalPages,
  });

  final List<CustomerReview> items;
  final int currentPage;
  final int totalPages;
}
