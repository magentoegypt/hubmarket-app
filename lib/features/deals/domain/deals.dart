import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../catalog/domain/money.dart';
import '../../catalog/domain/product.dart';

/// One page of `hmDeals`: products whose special price is live today, deepest
/// percentage discount first (Figma 10b).
@immutable
class DealsPage {
  const DealsPage({
    required this.items,
    required this.totalCount,
    this.pageInfo = const HmPageInfo(),
    this.countdownEndsAt,
  });

  final List<Product> items;

  /// Ranked deals available (the backend caps the ranking at 200).
  final int totalCount;
  final HmPageInfo pageInfo;

  /// The soonest offer end on this page (end of that day, store timezone).
  final DateTime? countdownEndsAt;

  static const DealsPage empty = DealsPage(items: <Product>[], totalCount: 0);
}

/// A bundle card (`HmBundleDeal`): a `bundle` or `new_bundle` product with
/// its real saving, as the website's bundle rail computes it.
@immutable
class BundleDeal {
  const BundleDeal({
    required this.uid,
    required this.sku,
    required this.name,
    required this.urlKey,
    required this.price,
    this.imageUrl,
    this.seller,
    this.description,
    this.isKit = true,
    this.itemCount = 0,
    this.thumbnails = const <String>[],
    this.moreThumbnails = 0,
    this.priceIsFrom = false,
    this.regularTotal,
    this.saving,
    this.discountPercent = 0,
    this.ratingPercent,
    this.reviewCount = 0,
    this.categoryIds = const <int>[],
  });

  final String uid;
  final String sku;
  final String name;
  final String urlKey;

  /// 16:9, absolute HTTPS.
  final String? imageUrl;
  final HmSellerSummary? seller;

  /// A plain excerpt, else the included products.
  final String? description;

  /// True: several required options (a kit); false: choose one.
  final bool isKit;

  /// Kit items, or the number of choices.
  final int itemCount;

  /// Up to four child thumbnails, and how many children are beyond them.
  final List<String> thumbnails;
  final int moreThumbnails;

  /// The indexed minimum price; [priceIsFrom] when the maximum is higher.
  final Money price;
  final bool priceIsFrom;

  /// The same items at regular prices; null without a real saving.
  final Money? regularTotal;
  final Money? saving;

  /// Rounded saving %, 0 when none.
  final int discountPercent;

  /// 0–100; null when unrated.
  final int? ratingPercent;
  final int reviewCount;
  final List<int> categoryIds;

  bool get hasSaving => (saving?.amount ?? 0) > 0 && discountPercent > 0;

  /// Out of 5, one decimal; null when unrated.
  double? get rating =>
      ratingPercent == null ? null : (ratingPercent! / 20 * 10).round() / 10;
}

/// A bundle filter chip (`HmCategoryCount`).
@immutable
class DealCategory {
  const DealCategory({
    required this.id,
    required this.uid,
    required this.name,
    required this.count,
  });

  final int id;
  final String uid;
  final String name;
  final int count;
}

/// One page of `hmBundleDeals` (Figma 10c).
@immutable
class BundleDealPage {
  const BundleDealPage({
    required this.items,
    this.categories = const <DealCategory>[],
    this.maxDiscountPercent = 0,
    this.sellerCount = 0,
    this.totalCount = 0,
    this.pageInfo = const HmPageInfo(),
  });

  final List<BundleDeal> items;

  /// Filter chips; empty when fewer than two.
  final List<DealCategory> categories;

  /// The largest discount; 0 hides the stat.
  final int maxDiscountPercent;
  final int sellerCount;
  final int totalCount;
  final HmPageInfo pageInfo;

  static const BundleDealPage empty = BundleDealPage(items: <BundleDeal>[]);
}
