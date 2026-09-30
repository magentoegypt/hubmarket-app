import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../catalog/domain/money.dart';
import '../../catalog/domain/product.dart';

/// How Today's Deals are ordered (`HmDealSort`), always over the day's whole
/// ranking on the server.
enum DealsSort {
  /// The ranking itself: deepest percentage discount first.
  biggestDiscount('DISCOUNT'),
  priceLowHigh('PRICE_ASC'),
  priceHighLow('PRICE_DESC'),

  /// Soonest-ending offer first; offers without an end last.
  endingSoon('ENDING_SOON'),

  /// Newest products first, as the storefront's "Newest" sort.
  newest('NEWEST');

  const DealsSort(this.wire);

  /// The `HmDealSort` value, written inline in the document.
  final String wire;
}

/// What Today's Deals are narrowed to (Figma 10b chips and Filters sheet).
@immutable
class DealsFilters {
  const DealsFilters({
    this.categoryId,
    this.minDiscount,
    this.sort = DealsSort.biggestDiscount,
  });

  /// A department chip's category id; null is "All deals".
  final int? categoryId;

  /// "N% or more"; null is any discount.
  final int? minDiscount;
  final DealsSort sort;

  /// Nothing narrows the list (the sort aside).
  bool get isEmpty => categoryId == null && minDiscount == null;

  /// Discount thresholds the Filters sheet offers ("N% or more"), as the
  /// catalogue filter sheet's.
  static const List<int> discountSteps = [20, 30, 40, 50];

  DealsFilters copyWith({
    Object? categoryId = _keep,
    Object? minDiscount = _keep,
    DealsSort? sort,
  }) => DealsFilters(
    categoryId: identical(categoryId, _keep)
        ? this.categoryId
        : categoryId as int?,
    minDiscount: identical(minDiscount, _keep)
        ? this.minDiscount
        : minDiscount as int?,
    sort: sort ?? this.sort,
  );

  static const Object _keep = Object();

  @override
  bool operator ==(Object other) =>
      other is DealsFilters &&
      other.categoryId == categoryId &&
      other.minDiscount == minDiscount &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(categoryId, minDiscount, sort);

  @override
  String toString() =>
      'DealsFilters(category: $categoryId, min: $minDiscount, ${sort.wire})';
}

/// One page of `hmDeals`: products whose special price is live today, in the
/// asked order, filtered on the server (Figma 10b).
@immutable
class DealsPage {
  const DealsPage({
    required this.items,
    required this.totalCount,
    this.pageInfo = const HmPageInfo(),
    this.countdownEndsAt,
    this.categories = const <DealCategory>[],
    this.filtered = true,
  });

  final List<Product> items;

  /// Deals matching the filters (the backend ranks at most 200 a day).
  final int totalCount;
  final HmPageInfo pageInfo;

  /// The soonest offer end on this page (end of that day, store timezone).
  final DateTime? countdownEndsAt;

  /// Department chips of the deals matching every filter but the category,
  /// catalogue order, with counts; empty when fewer than two.
  final List<DealCategory> categories;

  /// False from a HubApp older than the filters: the page is the plain
  /// ranking, and the screen offers no chips, sort or filters.
  final bool filtered;

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
