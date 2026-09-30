import 'package:flutter/foundation.dart';

import 'hubapp_models.dart';

/// `hmAppConfig` — the app settings of one store view (Stores › Configuration
/// › Hub Market App), read once per launch and store switch.
@immutable
class HmAppConfig {
  const HmAppConfig({
    required this.storeCode,
    this.locale = '',
    this.search = const HmSearchConfig(),
    this.algolia,
    this.contact = const HmContactConfig(),
    this.versions = const <HmVersionPolicy>[],
    this.maintenance = const HmMaintenance(),
    this.features = const <String, bool>{},
    this.capabilities,
    this.shipping = const HmShippingConfig(),
  });

  final String storeCode;

  /// e.g. `ar_SA`.
  final String locale;
  final HmSearchConfig search;

  /// Null when the store view doesn't search on Algolia.
  final HmAlgoliaConfig? algolia;
  final HmContactConfig contact;
  final List<HmVersionPolicy> versions;
  final HmMaintenance maintenance;

  /// Remote switches by code. A code the backend doesn't list is unset — see
  /// [flag].
  final Map<String, bool> features;

  /// The HubApp satellites the server runs (`vendors`, `bundle`, `returns`,
  /// `account` — see [HubAppCapability]); null when the server predates the
  /// list. A satellite can be off on its own, and a server without it
  /// rejects a whole document naming one of its fields, so a document shared
  /// with Build 1 (a product listing) gains a satellite's fields only when
  /// its code is listed here.
  final Set<String>? capabilities;

  /// Whether the server lists the satellite [code] — false when it lists
  /// others, and when it predates [capabilities].
  bool hasCapability(String code) => capabilities?.contains(code) ?? false;

  /// Shipping promises (the free-shipping threshold); empty from a backend
  /// older than them.
  final HmShippingConfig shipping;

  /// The switch [code] (`store_credit`, `returns`, `whatsapp_login`, `push`,
  /// …); null when the backend doesn't list it, so each feature picks its own
  /// default.
  bool? flag(String code) => features[code];

  /// The version policy of [platform], if the backend sent one.
  HmVersionPolicy? versionFor(HmPlatform? platform) {
    if (platform == null) return null;
    for (final policy in versions) {
      if (policy.platform == platform) return policy;
    }
    return null;
  }

  /// Throws [FormatException] without a `store_code` — not an hmAppConfig.
  factory HmAppConfig.fromJson(Map<String, dynamic> json) {
    final storeCode = hmString(json['store_code']);
    if (storeCode == null) {
      throw const FormatException('hmAppConfig without a store_code');
    }
    return HmAppConfig(
      storeCode: storeCode,
      locale: hmString(json['locale']) ?? '',
      search: HmSearchConfig.fromJson(json['search']),
      algolia: HmAlgoliaConfig.fromJson(json['algolia']),
      contact: HmContactConfig.fromJson(json['contact']),
      versions: [
        for (final item
            in json['version'] is List ? json['version'] as List : const [])
          if (HmVersionPolicy.fromJson(item) case final policy?) policy,
      ],
      maintenance: HmMaintenance.fromJson(json['maintenance']),
      features: {
        for (final item
            in json['features'] is List ? json['features'] as List : const [])
          if (item is Map<String, dynamic>)
            if (hmString(item['code']) case final code?)
              code: item['enabled'] == true,
      },
      capabilities: json['capabilities'] is List
          ? Set.unmodifiable(hmStrings(json['capabilities']))
          : null,
      shipping: HmShippingConfig.fromJson(json['shipping']),
    );
  }
}

/// `HmShippingConfig` — the store view's shipping promises.
@immutable
class HmShippingConfig {
  const HmShippingConfig({this.freeOver, this.currency});

  /// The cart subtotal that earns free shipping, the figure the storefront's
  /// mini-cart counts down to (the lowest threshold of the store's coupon-free
  /// free-shipping cart price rules); null when the store has none.
  final double? freeOver;

  /// [freeOver]'s currency, e.g. `AED`.
  final String? currency;

  static HmShippingConfig fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const HmShippingConfig();
    final freeOver = json['free_over'];
    if (freeOver is! Map<String, dynamic>) return const HmShippingConfig();
    final value = hmDouble(freeOver['value']);
    return HmShippingConfig(
      freeOver: value != null && value >= 0 ? value : null,
      currency: hmString(freeOver['currency']),
    );
  }
}

/// The codes of `hmAppConfig.capabilities`: which HubApp satellite serves a
/// feature.
abstract final class HubAppCapability {
  /// `MagentoEgypt_HubAppVendors`: stores, `hm_seller`, store reviews,
  /// contact and chips.
  static const String vendors = 'vendors';

  /// `MagentoEgypt_HubAppBundle`: `hmAddBundleToCart`.
  static const String bundle = 'bundle';

  /// `MagentoEgypt_HubAppOrders`: `CustomerOrder.hm_packages`.
  static const String orders = 'orders';

  /// `MagentoEgypt_HubAppReturns`.
  static const String returns = 'returns';

  /// `MagentoEgypt_HubAppAccount`.
  static const String account = 'account';
}

/// `HmSearchConfig`.
@immutable
class HmSearchConfig {
  const HmSearchConfig({this.hint, this.trendingTerms = const <String>[]});

  /// The search field placeholder; null → the app's own wording.
  final String? hint;

  /// In admin order, at most 10; empty → the app's own list.
  final List<String> trendingTerms;

  static HmSearchConfig fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const HmSearchConfig();
    return HmSearchConfig(
      hint: hmString(json['hint']),
      trendingTerms: hmStrings(json['trending_terms']),
    );
  }
}

/// `HmAlgoliaConfig` — the storefront's Algolia application, the **secured**
/// search key it gives guest browsers (valid 24 h, [validUntil]) and the store
/// view's index names. Never an admin key.
@immutable
class HmAlgoliaConfig {
  const HmAlgoliaConfig({
    required this.applicationId,
    required this.searchApiKey,
    required this.indexPrefix,
    required this.productIndex,
    required this.categoryIndex,
    required this.pageIndex,
    this.validUntil,
    this.layout,
  });

  final String applicationId;

  /// Public by design; never log it.
  final String searchApiKey;

  /// When [searchApiKey] expires (UTC); fetch hmAppConfig again before then.
  final DateTime? validUntil;
  final String indexPrefix;
  final String productIndex;
  final String categoryIndex;
  final String pageIndex;

  /// The storefront's search layout (facets, sorts, suggestions, …); null from
  /// a backend older than it, which leaves the app to read it elsewhere.
  final HmAlgoliaLayout? layout;

  /// Null without the application, the key or the products index.
  static HmAlgoliaConfig? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final app = hmString(json['application_id']);
    final key = hmString(json['search_api_key']);
    final products = hmString(json['product_index']);
    if (app == null || key == null || products == null) return null;
    final seconds = hmInt(json['valid_until']);
    return HmAlgoliaConfig(
      applicationId: app,
      searchApiKey: key,
      validUntil: seconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
      indexPrefix: hmString(json['index_prefix']) ?? '',
      productIndex: products,
      categoryIndex: hmString(json['category_index']) ?? '',
      pageIndex: hmString(json['page_index']) ?? '',
      layout: HmAlgoliaLayout.fromJson(json),
    );
  }
}

/// The search layout the storefront renders into `window.algoliaConfig` for
/// a guest, as `hmAppConfig.algolia` carries it (`facets`, `sorts`,
/// `suggestion_index`, …).
@immutable
class HmAlgoliaLayout {
  const HmAlgoliaLayout({
    this.facets = const <HmAlgoliaFacet>[],
    this.sorts = const <HmAlgoliaSort>[],
    this.suggestionIndex,
    this.suggestionCount = 0,
    this.currencyCode = '',
    this.priceGroup = '',
    this.maxValuesPerFacet = 0,
    this.productSuggestions = 0,
    this.categorySuggestions = 0,
    this.pageSuggestions = 0,
    this.categorySeparator = '',
    this.categoriesOutsideMenu = false,
  });

  /// In the admin's order, with the store view's labels.
  final List<HmAlgoliaFacet> facets;

  /// The products index's sort replicas for guests, in the admin's order;
  /// relevance is the products index itself.
  final List<HmAlgoliaSort> sorts;

  /// The query-suggestions index the storefront's autocomplete reads; null
  /// when its suggestions are off.
  final String? suggestionIndex;
  final int suggestionCount;
  final String currencyCode;
  final String priceGroup;
  final int maxValuesPerFacet;
  final int productSuggestions;
  final int categorySuggestions;
  final int pageSuggestions;

  /// As indexed, spaces included (` /// `).
  final String categorySeparator;
  final bool categoriesOutsideMenu;

  /// Null when [json] (an `HmAlgoliaConfig`) carries no layout — a backend
  /// older than it doesn't send `facets`.
  static HmAlgoliaLayout? fromJson(Map<String, dynamic> json) {
    final facets = json['facets'];
    if (facets is! List) return null;
    final sorts = json['sorts'];
    final separator = json['category_separator'];
    return HmAlgoliaLayout(
      facets: [
        for (final item in facets)
          if (HmAlgoliaFacet.fromJson(item) case final facet?) facet,
      ],
      sorts: [
        for (final item in sorts is List ? sorts : const [])
          if (HmAlgoliaSort.fromJson(item) case final sort?) sort,
      ],
      suggestionIndex: hmString(json['suggestion_index']),
      suggestionCount: _count(json['suggestion_count']),
      currencyCode: hmString(json['currency_code']) ?? '',
      priceGroup: hmString(json['price_group']) ?? '',
      maxValuesPerFacet: _count(json['max_values_per_facet']),
      productSuggestions: _count(json['product_suggestions']),
      categorySuggestions: _count(json['category_suggestions']),
      pageSuggestions: _count(json['page_suggestions']),
      categorySeparator: separator is String ? separator : '',
      categoriesOutsideMenu: json['categories_outside_menu'] == true,
    );
  }

  static int _count(Object? value) {
    final count = hmInt(value);
    return count != null && count > 0 ? count : 0;
  }
}

/// `HmAlgoliaFacet`.
@immutable
class HmAlgoliaFacet {
  const HmAlgoliaFacet({
    required this.attribute,
    required this.type,
    this.label = '',
  });

  /// `price`, `categories`, `mgs_brand`, …
  final String attribute;

  /// `slider`, `conjunctive`, `disjunctive` or `priceRanges`.
  final String type;

  /// In the store view's language; may be empty.
  final String label;

  static HmAlgoliaFacet? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final attribute = hmString(json['attribute']);
    if (attribute == null) return null;
    return HmAlgoliaFacet(
      attribute: attribute,
      type: hmString(json['type']) ?? '',
      label: hmString(json['label']) ?? '',
    );
  }
}

/// `HmAlgoliaSort` — a sort replica of the products index.
@immutable
class HmAlgoliaSort {
  const HmAlgoliaSort({
    required this.index,
    required this.attribute,
    required this.descending,
    this.label = '',
  });

  final String index;

  /// `price`, `created_at`, …
  final String attribute;
  final bool descending;
  final String label;

  static HmAlgoliaSort? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final index = hmString(json['index']);
    final attribute = hmString(json['attribute']);
    final direction = hmString(json['direction'])?.toUpperCase();
    if (index == null || attribute == null) return null;
    if (direction != 'ASC' && direction != 'DESC') return null;
    return HmAlgoliaSort(
      index: index,
      attribute: attribute,
      descending: direction == 'DESC',
      label: hmString(json['label']) ?? '',
    );
  }
}

/// `HmContactConfig` — customer-service channels; each may be missing.
@immutable
class HmContactConfig {
  const HmContactConfig({
    this.whatsappNumber,
    this.whatsappUrl,
    this.phone,
    this.email,
    this.hours,
  });

  /// E.164.
  final String? whatsappNumber;

  /// `https://wa.me/<digits>`.
  final String? whatsappUrl;

  /// E.164.
  final String? phone;
  final String? email;
  final String? hours;

  bool get isEmpty =>
      whatsappUrl == null && phone == null && email == null && hours == null;

  static HmContactConfig fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const HmContactConfig();
    final number = hmString(json['whatsapp_number']);
    final url = hmString(json['whatsapp_url']);
    return HmContactConfig(
      whatsappNumber: number,
      whatsappUrl:
          url ??
          (number == null
              ? null
              : 'https://wa.me/${number.replaceAll(RegExp(r'\D'), '')}'),
      phone: hmString(json['phone']),
      email: hmString(json['email']),
      hours: hmString(json['hours']),
    );
  }
}

/// `HmVersionPolicy` for one platform.
@immutable
class HmVersionPolicy {
  const HmVersionPolicy({
    required this.platform,
    this.minVersion,
    this.latestVersion,
    this.storeUrl,
    this.message,
  });

  final HmPlatform platform;

  /// Builds older than this must update.
  final String? minVersion;

  /// Builds older than this may be told an update exists.
  final String? latestVersion;
  final String? storeUrl;

  /// Update prompt, in the store view's language.
  final String? message;

  static HmVersionPolicy? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final platform = HmPlatform.parse(json['platform']);
    if (platform == null) return null;
    return HmVersionPolicy(
      platform: platform,
      minVersion: hmString(json['min_version']),
      latestVersion: hmString(json['latest_version']),
      storeUrl: hmString(json['store_url']),
      message: hmString(json['message']),
    );
  }

  /// Whether [appVersion] is below [minVersion]. False when either can't be
  /// read — an unreadable policy never locks anyone out.
  bool requiresUpdate(String? appVersion) {
    final cmp = compareVersions(appVersion, minVersion);
    return cmp != null && cmp < 0;
  }

  /// Whether a newer build than [appVersion] is published.
  bool hasUpdate(String? appVersion) {
    final cmp = compareVersions(appVersion, latestVersion);
    return cmp != null && cmp < 0;
  }
}

/// `HmMaintenance`.
@immutable
class HmMaintenance {
  const HmMaintenance({
    this.enabled = false,
    this.message,
    this.retryAfterMinutes,
  });

  final bool enabled;

  /// In the store view's language; null → the app's own wording.
  final String? message;
  final int? retryAfterMinutes;

  static HmMaintenance fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return const HmMaintenance();
    final minutes = hmInt(json['retry_after_minutes']);
    return HmMaintenance(
      enabled: json['enabled'] == true,
      message: hmString(json['message']),
      retryAfterMinutes: minutes != null && minutes > 0 ? minutes : null,
    );
  }
}

/// Compares two semantic versions by their numeric `major.minor.patch` parts
/// (a `-pre` / `+build` suffix is ignored; missing parts count as 0). Null
/// when either is missing or not a version at all.
int? compareVersions(String? a, String? b) {
  final left = _versionParts(a);
  final right = _versionParts(b);
  if (left == null || right == null) return null;
  for (var i = 0; i < 3; i++) {
    final diff = left[i].compareTo(right[i]);
    if (diff != 0) return diff;
  }
  return 0;
}

List<int>? _versionParts(String? version) {
  final match = RegExp(
    r'^\s*v?(\d+)(?:\.(\d+))?(?:\.(\d+))?',
  ).firstMatch(version ?? '');
  if (match == null) return null;
  return [
    int.parse(match.group(1)!),
    int.parse(match.group(2) ?? '0'),
    int.parse(match.group(3) ?? '0'),
  ];
}
