import 'package:flutter/foundation.dart';

import '../util/media.dart';

/// Types shared by every Hub Market App (`MagentoEgypt_HubApp*`) feature, as
/// the contract in `lib/core/graphql/hubapp.graphql` defines them. Feature-
/// specific types (Home sections, bundles, returns, …) live with their
/// feature; these are the ones several features read.
///
/// Parsing is tolerant: a missing or mistyped field becomes null / empty / 0
/// rather than throwing, and an enum value this build doesn't know maps to an
/// `unknown` member — the contract may grow before the app does.

/// `HmPlatform`.
enum HmPlatform {
  android('ANDROID'),
  ios('IOS');

  const HmPlatform(this.wire);

  /// The GraphQL enum value.
  final String wire;

  /// The platform this build runs on; null elsewhere (desktop, web, tests on
  /// a host platform are mapped by [defaultTargetPlatform]).
  static HmPlatform? get current => switch (defaultTargetPlatform) {
    TargetPlatform.android => HmPlatform.android,
    TargetPlatform.iOS => HmPlatform.ios,
    _ => null,
  };

  static HmPlatform? parse(Object? value) {
    for (final p in values) {
      if (p.wire == value) return p;
    }
    return null;
  }
}

/// `HmAudience` — marketing targeting of the Home, not authorisation.
enum HmAudience {
  guest('GUEST'),
  customer('CUSTOMER');

  const HmAudience(this.wire);
  final String wire;
}

/// `HmLinkType`: what an [HmLink] points at, classified server-side so the app
/// can route natively.
enum HmLinkType {
  category('CATEGORY'),
  product('PRODUCT'),
  cmsPage('CMS_PAGE'),
  store('STORE'),
  stores('STORES'),
  brand('BRAND'),
  brands('BRANDS'),
  bundles('BUNDLES'),
  deals('DEALS'),
  search('SEARCH'),
  external('EXTERNAL'),

  /// A value newer than this build: open [HmLink.url].
  unknown('');

  const HmLinkType(this.wire);
  final String wire;

  static HmLinkType parse(Object? value) {
    for (final t in values) {
      if (t != unknown && t.wire == value) return t;
    }
    return unknown;
  }
}

/// `HmLink` — a destination. [url] (absolute storefront URL) is always there
/// as the fallback; [uid] is set for CATEGORY and PRODUCT; [code] carries the
/// seller code (STORE), brand url_key (BRAND), CMS identifier (CMS_PAGE),
/// product url_key (PRODUCT) or search text (SEARCH).
@immutable
class HmLink {
  const HmLink({
    required this.type,
    required this.url,
    this.path,
    this.uid,
    this.code,
  });

  final HmLinkType type;
  final String url;
  final String? path;
  final String? uid;
  final String? code;

  /// Null without a JSON object or a url.
  static HmLink? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final url = hmString(json['url']);
    final type = HmLinkType.parse(json['type']);
    if (url == null && type == HmLinkType.unknown) return null;
    return HmLink(
      type: type,
      url: url ?? '',
      path: hmString(json['path']),
      uid: hmString(json['uid']),
      code: hmString(json['code']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HmLink &&
      other.type == type &&
      other.url == url &&
      other.path == path &&
      other.uid == uid &&
      other.code == code;

  @override
  int get hashCode => Object.hash(type, url, path, uid, code);

  @override
  String toString() => 'HmLink(${type.wire}, $url, uid: $uid, code: $code)';
}

/// `HmSellerSummary` — who sells an item (products, cart and order lines,
/// bundles, returns). [isMarketplace] is Hub Market itself (then [code],
/// [vendorEntityId] and [link] are null).
@immutable
class HmSellerSummary {
  const HmSellerSummary({
    required this.name,
    this.code,
    this.vendorEntityId,
    this.logoUrl,
    this.rating,
    this.reviewCount = 0,
    this.productCount = 0,
    this.isMarketplace = false,
    this.link,
  });

  final String? code;

  /// For `products(filter: {vendor_id: {match: "<id>", match_type: FULL}})`.
  final int? vendorEntityId;
  final String name;
  final String? logoUrl;

  /// Out of 5, one decimal; null when unrated.
  final double? rating;
  final int reviewCount;
  final int productCount;
  final bool isMarketplace;
  final HmLink? link;

  /// Null without a JSON object or a name.
  static HmSellerSummary? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final name = hmString(json['name']);
    if (name == null) return null;
    return HmSellerSummary(
      name: name,
      code: hmString(json['code']),
      vendorEntityId: hmInt(json['vendor_entity_id']),
      logoUrl: hmImageUrl(json['logo_url']),
      rating: hmDouble(json['rating']),
      reviewCount: hmInt(json['review_count']) ?? 0,
      productCount: hmInt(json['product_count']) ?? 0,
      isMarketplace: json['is_marketplace'] == true,
      link: HmLink.fromJson(json['link']),
    );
  }
}

/// `HmDispatchSource`.
enum HmDispatchSource { declared, measured, unknown }

/// `HmDispatchTime` — a seller's typical dispatch.
@immutable
class HmDispatchTime {
  const HmDispatchTime({
    required this.code,
    required this.label,
    this.source = HmDispatchSource.unknown,
  });

  /// `same_day`, `next_day`, `days_2_3`, `days_3_5`, `days_5_7`, `measured_<n>`.
  final String code;

  /// Short, in the store view's language.
  final String label;
  final HmDispatchSource source;

  static HmDispatchTime? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final code = hmString(json['code']);
    final label = hmString(json['label']);
    if (code == null || label == null) return null;
    return HmDispatchTime(
      code: code,
      label: label,
      source: switch (json['source']) {
        'DECLARED' => HmDispatchSource.declared,
        'MEASURED' => HmDispatchSource.measured,
        _ => HmDispatchSource.unknown,
      },
    );
  }
}

/// `HmCategoryCount` — a category with a count (bundle and store chips, a
/// seller's primary category).
@immutable
class HmCategoryCount {
  const HmCategoryCount({
    required this.id,
    required this.uid,
    required this.name,
    this.count = 0,
  });

  final int id;
  final String uid;

  /// In the store view's language.
  final String name;

  /// What is counted depends on the field: sellers for a Stores chip, the
  /// seller's products for a primary category.
  final int count;

  /// Null without a JSON object, a uid or a name.
  static HmCategoryCount? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final uid = hmString(json['uid']);
    final name = hmString(json['name']);
    if (uid == null || name == null) return null;
    return HmCategoryCount(
      id: hmInt(json['id']) ?? 0,
      uid: uid,
      name: name,
      count: hmInt(json['count']) ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HmCategoryCount &&
      other.id == id &&
      other.uid == uid &&
      other.name == name &&
      other.count == count;

  @override
  int get hashCode => Object.hash(id, uid, name, count);
}

/// `HmStoreCard` — a seller card (Home store sections, the stores list, the
/// head of a store page).
@immutable
class HmStoreCard {
  const HmStoreCard({
    required this.code,
    required this.vendorEntityId,
    required this.name,
    required this.link,
    this.logoUrl,
    this.rating,
    this.reviewCount = 0,
    this.productCount = 0,
    this.dispatchTime,
    this.isFeatured = false,
    this.joinedAt,
    this.primaryCategory,
    this.facetValue,
  });

  final String code;

  /// For `products(filter: {vendor_id: {match: "<id>", match_type: FULL}})`.
  final int vendorEntityId;
  final String name;
  final String? logoUrl;

  /// Out of 5; null when unrated.
  final double? rating;
  final int reviewCount;
  final int productCount;
  final HmDispatchTime? dispatchTime;
  final bool isFeatured;

  /// Joined, UTC.
  final DateTime? joinedAt;
  final HmLink link;

  /// The top-level category holding most of the seller's products, with how
  /// many ("Furniture · 38 products"); null without one, or when the list
  /// didn't ask ([HmFragments.storeCardExtras]).
  final HmCategoryCount? primaryCategory;

  /// The seller's value in the storefront's Algolia seller facet — what a
  /// search's seller counts are keyed by; null when the list didn't ask or
  /// the records carry no seller.
  final String? facetValue;

  /// Null without a code, a name or a link.
  static HmStoreCard? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final code = hmString(json['code']);
    final name = hmString(json['name']);
    final link = HmLink.fromJson(json['link']);
    if (code == null || name == null || link == null) return null;
    return HmStoreCard(
      code: code,
      vendorEntityId: hmInt(json['vendor_entity_id']) ?? 0,
      name: name,
      link: link,
      logoUrl: hmImageUrl(json['logo_url']),
      rating: hmDouble(json['rating']),
      reviewCount: hmInt(json['review_count']) ?? 0,
      productCount: hmInt(json['product_count']) ?? 0,
      dispatchTime: HmDispatchTime.fromJson(json['dispatch_time']),
      isFeatured: json['is_featured'] == true,
      joinedAt: hmDateTime(json['joined_at']),
      primaryCategory: HmCategoryCount.fromJson(json['primary_category']),
      // Kept as sent: facet values are compared exactly.
      facetValue: json['facet_value'] is String &&
              (json['facet_value'] as String).isNotEmpty
          ? json['facet_value'] as String
          : null,
    );
  }
}

/// `SearchResultPageInfo` of an hm* page.
@immutable
class HmPageInfo {
  const HmPageInfo({
    this.currentPage = 1,
    this.pageSize = 0,
    this.totalPages = 1,
  });

  final int currentPage;
  final int pageSize;
  final int totalPages;

  bool get hasMore => currentPage < totalPages;

  static HmPageInfo fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const HmPageInfo();
    return HmPageInfo(
      currentPage: hmInt(json['current_page']) ?? 1,
      pageSize: hmInt(json['page_size']) ?? 0,
      totalPages: hmInt(json['total_pages']) ?? 1,
    );
  }
}

/// GraphQL fragments for the shared types, to append to a document that
/// spreads them. Fragment names are app-wide (`tool/validate_ops.py` resolves
/// spreads across files), so keep these unique.
abstract final class HmFragments {
  /// `...HmLinkFields` on any `HmLink`.
  static const String link =
      r'''fragment HmLinkFields on HmLink{type url path uid code}''';

  /// `...HmSellerFields` on any `HmSellerSummary` (spreads [link]).
  static const String seller =
      r'''fragment HmSellerFields on HmSellerSummary{code vendor_entity_id name logo_url rating review_count product_count is_marketplace link{...HmLinkFields}}''';

  /// `...HmStoreCardFields` on any `HmStoreCard` (spreads [link]).
  static const String storeCard =
      r'''fragment HmStoreCardFields on HmStoreCard{code vendor_entity_id name logo_url rating review_count product_count dispatch_time{code label source} is_featured joined_at link{...HmLinkFields}}''';

  /// `...HmStoreCardExtras` on any `HmStoreCard`: the primary category and
  /// the Algolia facet value. Spread beside [storeCard] only while the
  /// server lists the `vendors` capability — a server from before them
  /// rejects the whole document.
  static const String storeCardExtras =
      r'''fragment HmStoreCardExtras on HmStoreCard{primary_category{id uid name count} facet_value}''';

  /// `...HmCardSeller` on any product: who sells it, for the listing card's
  /// seller line (spreads [seller]). Added to listing documents by
  /// `SellerSelections.withCardSellers` only while the server lists the
  /// `vendors` capability.
  static const String cardSeller =
      r'''fragment HmCardSeller on ProductInterface{hm_seller{...HmSellerFields}}''';
}

// ───────────────────────────────────────────── tolerant JSON readers

/// A trimmed non-empty string, else null.
String? hmString(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

int? hmInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v.trim()),
  _ => null,
};

double? hmDouble(Object? value) => switch (value) {
  final num v => v.toDouble(),
  final String v => double.tryParse(v.trim()),
  _ => null,
};

/// An absolute image URL upgraded to HTTPS, else null.
String? hmImageUrl(Object? value) => httpsMediaUrl(hmString(value));

/// An ISO-8601 instant (offset or `Z` honoured); null when unreadable.
DateTime? hmDateTime(Object? value) {
  final text = hmString(value);
  return text == null ? null : DateTime.tryParse(text);
}

/// The strings of a JSON list, blanks dropped.
List<String> hmStrings(Object? value) => [
  for (final item in value is List ? value : const <Object?>[])
    if (hmString(item) case final text?) text,
];
