import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../core/config/app_config.dart';

/// A facet configured for the storefront's search (Magento › Stores ›
/// Configuration › Algolia Search › Instant Search Results Page › Facets),
/// with its label in the store view's language.
@immutable
class AlgoliaFacet {
  const AlgoliaFacet({
    required this.attribute,
    required this.type,
    this.label = '',
  });

  /// The record attribute: `price`, `categories`, `mgs_brand`, `color`, …
  final String attribute;

  /// `slider`, `conjunctive`, `disjunctive` or `priceRanges`.
  final String type;
  final String label;

  bool get isRange => type == 'slider' || type == 'priceRanges';

  Map<String, Object?> toJson() => {
    'attribute': attribute,
    'type': type,
    'label': label,
  };
}

/// A sort replica of the products index (Algolia › Instant Search › Sorts).
@immutable
class AlgoliaSortIndex {
  const AlgoliaSortIndex({
    required this.indexName,
    required this.attribute,
    required this.descending,
    this.label = '',
  });

  final String indexName;

  /// `price`, `created_at`, …
  final String attribute;
  final bool descending;

  /// The admin's label in the store view's language; empty when unknown.
  final String label;

  Map<String, Object?> toJson() => {
    'name': indexName,
    'attribute': attribute,
    'sort': descending ? 'desc' : 'asc',
    'label': label,
  };
}

/// Everything the app needs to search a store view's Algolia indices: the
/// application, the search key, the index name, and the facets and sorts
/// configured in Magento.
///
/// It comes from the storefront's `window.algoliaConfig` (the same object the
/// website's autocomplete reads, see [AlgoliaSettings.fromStorefrontConfig])
/// or, when a static key is configured, from [AppConfig].
@immutable
class AlgoliaSettings {
  const AlgoliaSettings({
    required this.appId,
    required this.searchKey,
    required this.indexName,
    this.validUntil,
    this.facets = const <AlgoliaFacet>[],
    this.sorts = const <AlgoliaSortIndex>[],
    this.currencyCode = 'AED',
    this.priceGroup = 'default',
    this.productSuggestions = 8,
    this.categorySuggestions = 2,
    this.pageSuggestions = 2,
    this.maxValuesPerFacet = 10,
    this.categorySeparator = ' /// ',
    this.categoriesOutsideMenu = false,
    this.fromBackend = true,
  });

  final String appId;

  /// Public by design; never log it.
  final String searchKey;

  /// Prefix + store code, e.g. `hubmarket_en`.
  final String indexName;

  /// When the key stops working — a secured key's `validUntil`; null for a
  /// key with no expiry.
  final DateTime? validUntil;

  final List<AlgoliaFacet> facets;

  /// Sort replicas, in the admin's order. Relevance (the primary index) is
  /// always offered first and is not listed here.
  final List<AlgoliaSortIndex> sorts;
  final String currencyCode;

  /// The customer group whose prices the records hold for guests.
  final String priceGroup;

  /// How many products, categories and pages the website's autocomplete
  /// shows (Algolia › Autocomplete).
  final int productSuggestions;
  final int categorySuggestions;
  final int pageSuggestions;

  final int maxValuesPerFacet;

  /// Between the levels of a `categories.levelN` path: `Furniture /// Sofas`.
  final String categorySeparator;

  /// "Show categories that are not included in the navigation menu".
  final bool categoriesOutsideMenu;

  /// False for settings built from [AppConfig] alone.
  final bool fromBackend;

  /// A key this close to its `validUntil` is treated as expired.
  static const Duration expiryMargin = Duration(minutes: 2);

  String get productsIndex => '${indexName}_products';
  String get categoriesIndex => '${indexName}_categories';
  String get pagesIndex => '${indexName}_pages';

  /// The numeric price attribute of the records, e.g. `price.AED.default`.
  String get priceAttribute => 'price.$currencyCode.$priceGroup';

  /// The configured facet for [attribute], if any.
  AlgoliaFacet? facet(String attribute) {
    for (final facet in facets) {
      if (facet.attribute == attribute) return facet;
    }
    return null;
  }

  /// Whether these settings can search at [now].
  bool usableAt(DateTime now) =>
      appId.isNotEmpty &&
      searchKey.isNotEmpty &&
      indexName.isNotEmpty &&
      (validUntil == null || now.isBefore(validUntil!.subtract(expiryMargin)));

  /// Reads the storefront's `window.algoliaConfig`. Throws [FormatException]
  /// when the application, key or index is missing.
  factory AlgoliaSettings.fromStorefrontConfig(Map<String, dynamic> config) {
    String text(Object? value) => value is String ? value.trim() : '';
    int count(Object? value, int orElse) =>
        value is num ? value.toInt() : int.tryParse('$value') ?? orElse;

    final appId = text(config['applicationId']);
    final key = text(config['apiKey']);
    final indexName = text(config['indexName']);
    if (appId.isEmpty || key.isEmpty || indexName.isEmpty) {
      throw const FormatException('algoliaConfig lacks the app, key or index');
    }

    final autocomplete = config['autocomplete'] is Map<String, dynamic>
        ? config['autocomplete'] as Map<String, dynamic>
        : const <String, dynamic>{};
    var pages = 0;
    for (final section in autocomplete['sections'] as List<dynamic>? ?? []) {
      if (section is Map<String, dynamic> && section['name'] == 'pages') {
        pages = count(section['hitsPerPage'], 2);
      }
    }
    final instant = config['instant'] is Map<String, dynamic>
        ? config['instant'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final separator = text(instant['categorySeparator']);

    return AlgoliaSettings(
      appId: appId,
      searchKey: key,
      indexName: indexName,
      validUntil: securedKeyValidUntil(key),
      facets: [
        for (final facet in config['facets'] as List<dynamic>? ?? [])
          if (facet is Map<String, dynamic> &&
              text(facet['attribute']).isNotEmpty)
            AlgoliaFacet(
              attribute: text(facet['attribute']),
              type: text(facet['type']),
              label: text(facet['label']),
            ),
      ],
      sorts: [
        for (final sort in config['sortingIndices'] as List<dynamic>? ?? [])
          if (sort is Map<String, dynamic> &&
              text(sort['name']).isNotEmpty &&
              text(sort['attribute']).isNotEmpty)
            AlgoliaSortIndex(
              indexName: text(sort['name']),
              attribute: text(sort['attribute']),
              descending: text(sort['sort']).toLowerCase() == 'desc',
              label: text(sort['label']),
            ),
      ],
      currencyCode: text(config['currencyCode']).isEmpty
          ? 'AED'
          : text(config['currencyCode']),
      priceGroup: text(config['priceGroup']).isEmpty
          ? 'default'
          : text(config['priceGroup']),
      productSuggestions: count(autocomplete['nbOfProductsSuggestions'], 8),
      categorySuggestions: count(autocomplete['nbOfCategoriesSuggestions'], 2),
      pageSuggestions: pages,
      maxValuesPerFacet: count(config['maxValuesPerFacet'], 10),
      categorySeparator: separator.isEmpty ? ' /// ' : ' $separator ',
      categoriesOutsideMenu: config['showCatsNotIncludedInNavigation'] == true,
    );
  }

  /// Settings from compile-time values alone, for a static search-only key
  /// ([AppConfig.algoliaSearchKey]). Facets beyond price, category and rating
  /// need their store-view labels from the backend, so they are left out.
  factory AlgoliaSettings.fromAppConfig(AppConfig config, String storeCode) {
    final indexName = '${config.algoliaIndexPrefix.trim()}$storeCode';
    return AlgoliaSettings(
      appId: config.algoliaAppId.trim(),
      searchKey: config.algoliaSearchKey.trim(),
      indexName: indexName,
      validUntil: securedKeyValidUntil(config.algoliaSearchKey.trim()),
      facets: const <AlgoliaFacet>[
        AlgoliaFacet(attribute: 'price', type: 'slider'),
        AlgoliaFacet(attribute: 'categories', type: 'conjunctive'),
        AlgoliaFacet(attribute: 'rating_summary', type: 'slider'),
      ],
      sorts: [
        for (final suffix in config.algoliaSortReplicaSuffixes)
          if (sortIndexFromSuffix('${indexName}_products', suffix)
              case final sort?)
            sort,
      ],
      fromBackend: false,
    );
  }

  /// The subset of `algoliaConfig` these settings came from, for
  /// [fromStorefrontConfig] to read back (the offline cache).
  Map<String, Object?> toStorefrontConfig() => {
    'applicationId': appId,
    'apiKey': searchKey,
    'indexName': indexName,
    'facets': [for (final facet in facets) facet.toJson()],
    'sortingIndices': [for (final sort in sorts) sort.toJson()],
    'currencyCode': currencyCode,
    'priceGroup': priceGroup,
    'maxValuesPerFacet': maxValuesPerFacet,
    'showCatsNotIncludedInNavigation': categoriesOutsideMenu,
    'instant': {'categorySeparator': categorySeparator.trim()},
    'autocomplete': {
      'nbOfProductsSuggestions': productSuggestions,
      'nbOfCategoriesSuggestions': categorySuggestions,
      'sections': [
        {'name': 'pages', 'hitsPerPage': pageSuggestions},
      ],
    },
  };
}

/// The sort replica named `<productsIndex>_<suffix>`: `price_default_asc` is
/// price ascending (for the `default` customer group), `created_at_desc`
/// newest first. Null for a suffix without a direction.
AlgoliaSortIndex? sortIndexFromSuffix(String productsIndex, String suffix) {
  final parts = suffix.split('_');
  if (parts.length < 2) return null;
  final direction = parts.last.toLowerCase();
  if (direction != 'asc' && direction != 'desc') return null;
  final attribute = parts.first == 'price'
      ? 'price'
      : parts.sublist(0, parts.length - 1).join('_');
  return AlgoliaSortIndex(
    indexName: '${productsIndex}_$suffix',
    attribute: attribute,
    descending: direction == 'desc',
  );
}

/// When an Algolia *secured* API key expires, or null when [key] has no
/// `validUntil` (a plain key, or a secured key without one).
///
/// A secured key is base64 of a 64-hex-character HMAC followed by the query
/// parameters it enforces, e.g. `tagFilters=&validUntil=1790756245`.
DateTime? securedKeyValidUntil(String key) {
  if (key.isEmpty) return null;
  final String decoded;
  try {
    decoded = utf8.decode(base64.decode(base64.normalize(key.trim())));
  } on FormatException {
    return null;
  }
  if (decoded.length <= 64 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(decoded.substring(0, 64))) {
    return null;
  }
  final params = Uri.splitQueryString(decoded.substring(64));
  final seconds = int.tryParse(params['validUntil'] ?? '');
  return seconds == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

/// The object a storefront page assigns to `window.algoliaConfig`, or null
/// when [html] has none.
///
/// Magento renders it as `window.algoliaConfig = JSON.parse('…')`, the JSON
/// inside a JavaScript string literal whose quotes and non-ASCII characters
/// are `\uXXXX`-escaped; the literal is unescaped here, then decoded.
Map<String, dynamic>? algoliaConfigFromHtml(String html) {
  final assignment = RegExp(
    r'''window\.algoliaConfig\s*=\s*JSON\.parse\(\s*(['"])''',
  ).firstMatch(html);
  if (assignment == null) return null;
  final quote = assignment.group(1)!;
  final literal = StringBuffer();
  var i = assignment.end;
  var closed = false;
  while (i < html.length) {
    final char = html[i];
    if (char == quote) {
      closed = true;
      break;
    }
    if (char != r'\') {
      literal.write(char);
      i++;
      continue;
    }
    if (i + 1 >= html.length) break;
    final next = html[i + 1];
    switch (next) {
      case 'u':
        final hex = html.length >= i + 6 ? html.substring(i + 2, i + 6) : '';
        final code = int.tryParse(hex, radix: 16);
        if (hex.length != 4 || code == null) return null;
        literal.writeCharCode(code);
        i += 6;
      case 'x':
        final hex = html.length >= i + 4 ? html.substring(i + 2, i + 4) : '';
        final code = int.tryParse(hex, radix: 16);
        if (hex.length != 2 || code == null) return null;
        literal.writeCharCode(code);
        i += 4;
      case 'n':
        literal.write('\n');
        i += 2;
      case 'r':
        literal.write('\r');
        i += 2;
      case 't':
        literal.write('\t');
        i += 2;
      case 'b':
        literal.write('\b');
        i += 2;
      case 'f':
        literal.write('\f');
        i += 2;
      case '\n':
        // A line continuation.
        i += 2;
      default:
        // \\ \' \" \/ and any other escaped character stand for themselves.
        literal.write(next);
        i += 2;
    }
  }
  if (!closed) return null;
  try {
    final decoded = jsonDecode(literal.toString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
