import 'package:flutter/foundation.dart' show immutable;

import '../../../core/hubapp/hubapp.dart';

/// The product a seller's review is about (`HmStoreReviewProduct`).
@immutable
class StoreReviewProduct {
  const StoreReviewProduct({required this.name, this.urlKey, this.thumbnailUrl});

  /// In the store view's language.
  final String name;

  /// Null when the storefront no longer lists the product: named, not opened.
  final String? urlKey;
  final String? thumbnailUrl;

  static StoreReviewProduct? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = hmString(json['name']);
    if (name == null) return null;
    return StoreReviewProduct(
      name: name,
      urlKey: hmString(json['url_key']),
      thumbnailUrl: hmImageUrl(json['thumbnail_url']),
    );
  }
}

/// One review of a seller's product (`HmStoreReview`).
@immutable
class StoreReview {
  const StoreReview({
    required this.id,
    required this.nickname,
    this.title,
    this.text,
    this.rating,
    this.createdAt,
    this.product,
  });

  final int id;
  final String nickname;
  final String? title;
  final String? text;

  /// Its votes' average out of 5; null without votes.
  final double? rating;

  /// Written, UTC.
  final DateTime? createdAt;
  final StoreReviewProduct? product;

  /// Whole stars for the five-star row.
  int get stars => (rating ?? 0).round().clamp(0, 5);

  static StoreReview? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = hmInt(json['id']);
    if (id == null) return null;
    return StoreReview(
      id: id,
      nickname: hmString(json['nickname']) ?? '',
      title: hmString(json['title']),
      text: hmString(json['text']),
      rating: hmDouble(json['rating']),
      createdAt: hmDateTime(json['created_at']),
      product: StoreReviewProduct.fromJson(json['product']),
    );
  }
}

/// One page of `hmStoreReviews`: the seller's rating as the card counts it,
/// and the reviews this store view shows.
@immutable
class StoreReviewPage {
  const StoreReviewPage({
    this.rating,
    this.reviewCount = 0,
    this.items = const <StoreReview>[],
    this.totalCount = 0,
    this.pageInfo = const HmPageInfo(),
  });

  /// The seller's rating out of 5 (every store view); null when unrated.
  final double? rating;

  /// Approved reviews in every store view — the header's figure.
  final int reviewCount;
  final List<StoreReview> items;

  /// Reviews this store view shows; fewer than [reviewCount] when some were
  /// written on the other store view.
  final int totalCount;
  final HmPageInfo pageInfo;

  static const StoreReviewPage empty = StoreReviewPage(
    pageInfo: HmPageInfo(totalPages: 0),
  );

  /// Null for anything that isn't one (the code is no approved seller).
  static StoreReviewPage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final summary = json['summary'];
    final items = <StoreReview>[
      for (final item in json['items'] is List ? json['items'] as List : const [])
        if (StoreReview.fromJson(item) case final review?) review,
    ];
    return StoreReviewPage(
      rating: summary is Map<String, dynamic> ? hmDouble(summary['rating']) : null,
      reviewCount: summary is Map<String, dynamic>
          ? hmInt(summary['review_count']) ?? 0
          : 0,
      items: items,
      totalCount: hmInt(json['total_count']) ?? items.length,
      pageInfo: HmPageInfo.fromJson(json['page_info']),
    );
  }
}

/// `hmStoreCategories`: the Stores chips with how many sellers each holds.
@immutable
class StoreCategoryChips {
  const StoreCategoryChips({
    this.totalCount = 0,
    this.items = const <HmCategoryCount>[],
  });

  /// Sellers with a listable product: the All chip.
  final int totalCount;

  /// In menu order; none without sellers.
  final List<HmCategoryCount> items;

  static StoreCategoryChips fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const StoreCategoryChips();
    return StoreCategoryChips(
      totalCount: hmInt(json['total_count']) ?? 0,
      items: [
        for (final item
            in json['items'] is List ? json['items'] as List : const [])
          if (HmCategoryCount.fromJson(item) case final chip?)
            if (chip.count > 0) chip,
      ],
    );
  }
}
