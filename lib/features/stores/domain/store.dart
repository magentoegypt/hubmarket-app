import 'package:flutter/foundation.dart' show immutable;

import '../../../core/hubapp/hubapp.dart';

/// What the store screens read off a seller card ([HmStoreCard], shared with
/// the Home's store sections).
///
/// Every seller the backend lists is approved (Vnecoms status 2), which is the
/// only signal the website's VERIFIED mark reads too — so the app shows the
/// mark on every card, as the storefront does, rather than inventing a flag.
extension StoreCardX on HmStoreCard {
  /// Rated sellers show "★ 4.8"; the backend sends null when unrated.
  bool get isRated => (rating ?? 0) > 0;

  /// The letter the logo placeholder shows, as the website's avatar fallback
  /// does: the name's first character, `?` for an empty name.
  String get initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  /// The seller's storefront page — what Share sends; null without one.
  String? get webUrl => link.url.trim().isEmpty ? null : link.url;
}

/// A seller's store page (`HmStore`): the card plus the banner, the texts and
/// the policies. The HTML fields are drawn by the native CMS renderer.
@immutable
class StoreProfile {
  const StoreProfile({
    required this.card,
    this.bannerUrl,
    this.shortDescription,
    this.aboutHtml,
    this.shippingPolicyHtml,
    this.refundPolicyHtml,
  });

  final HmStoreCard card;
  final String? bannerUrl;

  /// Store Information › short description, plain text.
  final String? shortDescription;

  /// The "About" page, when the seller shows one.
  final String? aboutHtml;

  /// Shipping and refund policies, each only when the seller enabled it.
  final String? shippingPolicyHtml;
  final String? refundPolicyHtml;

  bool get hasPolicies =>
      shippingPolicyHtml != null || refundPolicyHtml != null;

  /// Null without a JSON object or a usable card.
  static StoreProfile? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final card = HmStoreCard.fromJson(json['card']);
    if (card == null) return null;
    return StoreProfile(
      card: card,
      bannerUrl: hmImageUrl(json['banner_url']),
      shortDescription: hmString(json['short_description']),
      aboutHtml: hmString(json['about_html']),
      shippingPolicyHtml: hmString(json['shipping_policy_html']),
      refundPolicyHtml: hmString(json['refund_policy_html']),
    );
  }
}

/// One page of `hmStores`.
@immutable
class StoreListPage {
  const StoreListPage({
    required this.items,
    required this.totalCount,
    this.pageInfo = const HmPageInfo(),
  });

  final List<HmStoreCard> items;
  final int totalCount;
  final HmPageInfo pageInfo;

  bool get hasMore => pageInfo.hasMore;

  static const StoreListPage empty = StoreListPage(
    items: <HmStoreCard>[],
    totalCount: 0,
    pageInfo: HmPageInfo(totalPages: 0),
  );

  /// `HmStorePage`; cards the app can't open (no code, name or link) are
  /// dropped.
  static StoreListPage fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return empty;
    final items = <HmStoreCard>[
      for (final item
          in json['items'] is List ? json['items'] as List : const [])
        if (HmStoreCard.fromJson(item) case final card?) card,
    ];
    return StoreListPage(
      items: items,
      totalCount: hmInt(json['total_count']) ?? items.length,
      pageInfo: HmPageInfo.fromJson(json['page_info']),
    );
  }
}

/// The orders `hmStores` can sort by (`HmStoreSort`).
enum StoreSort {
  /// Featured first, then rating, then name — the backend's default.
  featured('FEATURED'),

  /// Rating, then review count; unrated sellers last.
  topRated('TOP_RATED'),

  /// Newest sellers first.
  newest('NEWEST'),

  /// Localised name A–Z.
  name('NAME'),

  /// Most listable products first.
  productCount('PRODUCT_COUNT');

  const StoreSort(this.wire);

  /// The `HmStoreSort` enum value.
  final String wire;
}

/// What a store list asks `hmStores` for; keys the list providers, so it has
/// value equality.
@immutable
class StoreListQuery {
  const StoreListQuery({
    this.categoryId,
    this.name,
    this.featured,
    this.sort = StoreSort.featured,
  });

  /// Sellers with a listable product in this category or its children.
  final int? categoryId;

  /// A substring of the display name or code.
  final String? name;

  /// Only sellers flagged Show on Home.
  final bool? featured;
  final StoreSort sort;

  String get trimmedName => name?.trim() ?? '';

  /// The filter as the list document's scalar variables. The backend ignores
  /// a null filter field, so all three are always sent.
  Map<String, dynamic> toVariables() => <String, dynamic>{
    'featured': featured,
    'categoryId': categoryId,
    'name': trimmedName.isEmpty ? null : trimmedName,
  };

  @override
  bool operator ==(Object other) =>
      other is StoreListQuery &&
      other.categoryId == categoryId &&
      other.trimmedName == trimmedName &&
      other.featured == featured &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(categoryId, trimmedName, featured, sort);
}
