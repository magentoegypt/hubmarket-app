import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../marketplace/marketplace_features.dart';
import '../../domain/aggregation.dart';
import '../../domain/category.dart';
import '../../domain/search_facets.dart';
import '../../domain/search_highlight.dart';
import '../../domain/search_results.dart';
import 'algolia_client.dart';
import 'algolia_hits.dart';
import 'algolia_settings.dart';
import 'algolia_settings_repository.dart';

/// The attribute of the products index holding a record's category ids — the
/// facet the app scopes, filters and counts categories by.
const String kAlgoliaCategoryIds = 'categoryIds';

/// Record fields a product hit needs; the rest (descriptions, every child
/// SKU's attributes) stays on Algolia's side.
const List<String> _productFields = <String>[
  'name',
  'url',
  'sku',
  'type_id',
  'image_url',
  'thumbnail_url',
  'price',
  'categories',
  'in_stock',
  'rating_summary',
  // The card's seller line (AlgoliaVendor): shown only while the server lists
  // HubAppVendors, see ProductCard.
  'seller',
  'seller_url_key',
];

/// Most values a facet brings back — enough for the Categories tab and the
/// filter lists, whatever the admin's smaller "max values per facet".
int _maxValuesPerFacet(AlgoliaSettings settings) =>
    math.max(settings.maxValuesPerFacet, 20);

/// A facet value as `facetFilters` takes it. A leading `-` would negate the
/// filter, so it is escaped.
String _facetFilter(String attribute, String value) =>
    '$attribute:${value.startsWith('-') ? '\\$value' : value}';

/// The type-ahead's searches (Figma 09), as the website's autocomplete runs
/// them in one round trip: products (with the category facet for the "See
/// products in …" line), categories whose names match, and CMS pages.
/// [scopeUid] narrows the products to one category.
List<AlgoliaQuery> typeAheadQueries(
  AlgoliaSettings settings, {
  required String query,
  String? scopeUid,
}) {
  final scopeId = scopeUid == null ? null : categoryIdFromUid(scopeUid);
  return [
    AlgoliaQuery(settings.productsIndex, {
      'query': query,
      'hitsPerPage': settings.productSuggestions,
      'facets': [kAlgoliaCategoryIds],
      'maxValuesPerFacet': _maxValuesPerFacet(settings),
      'numericFilters': ['visibility_search=1'],
      if (scopeId != null)
        'facetFilters': [_facetFilter(kAlgoliaCategoryIds, scopeId)],
      'attributesToRetrieve': _productFields,
      'attributesToHighlight': ['name'],
      'highlightPreTag': kHighlightPreTag,
      'highlightPostTag': kHighlightPostTag,
      'analyticsTags': ['app', 'autocomplete'],
    }),
    if (settings.categorySuggestions > 0)
      AlgoliaQuery(settings.categoriesIndex, {
        'query': query,
        'hitsPerPage': settings.categorySuggestions,
        if (!settings.categoriesOutsideMenu)
          'numericFilters': ['include_in_menu=1'],
        'attributesToRetrieve': [
          'name',
          'path',
          'level',
          'url',
          'product_count',
        ],
        'attributesToHighlight': <String>[],
        'analyticsTags': ['app', 'autocomplete'],
      }),
    if (settings.pageSuggestions > 0)
      AlgoliaQuery(settings.pagesIndex, {
        'query': query,
        'hitsPerPage': settings.pageSuggestions,
        'attributesToRetrieve': ['name', 'url'],
        'attributesToHighlight': <String>[],
        'attributesToSnippet': <String>[],
        'analyticsTags': ['app', 'autocomplete'],
      }),
  ];
}

/// The type-ahead's answer from [results] (one per [typeAheadQueries] query).
TypeAheadResult typeAheadFromResults(
  AlgoliaSettings settings,
  List<Map<String, dynamic>> results, {
  required String query,
  required DateTime now,
  String? scopeUid,
  List<Category> tree = const <Category>[],
}) {
  final products = results.first;
  var next = 1;
  final categories = settings.categorySuggestions > 0 ? results[next++] : null;
  final pages = settings.pageSuggestions > 0 ? results[next++] : null;

  List<Map<String, dynamic>> hitsOf(Map<String, dynamic>? result) =>
      (result?['hits'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);

  return TypeAheadResult(
    engine: SearchEngine.algolia,
    products: [
      for (final hit in hitsOf(products))
        if (productHitFromAlgolia(hit, settings, now: now, query: query)
            case final row?)
          row,
    ],
    totalCount: (products['nbHits'] as num?)?.toInt() ?? 0,
    resultCategories: searchCategoriesFromIds(
      facetCounts(products['facets'], kAlgoliaCategoryIds),
      tree,
      excludeUid: scopeUid,
    ),
    categoryChips: [
      for (final hit in hitsOf(categories))
        if (categoryFromAlgoliaHit(hit) case final category?) category,
    ],
    pages: [
      for (final hit in hitsOf(pages))
        if (pageFromAlgoliaHit(hit) case final page?) page,
    ],
  );
}

/// The "Try" suggestions of a search that found nothing (Figma S2): queries
/// from the store's query-suggestions index ([AlgoliaSettings.suggestionIndex],
/// the one the website's autocomplete reads) that share words with [query],
/// every word optional when none shares them all. Null when the store has no
/// suggestions index — the page then shows no "Try" row.
AlgoliaQuery? trySuggestionsQuery(
  AlgoliaSettings settings, {
  required String query,
  int limit = 3,
}) {
  final index = settings.suggestionIndex;
  if (index == null || query.trim().isEmpty || limit < 1) return null;
  return AlgoliaQuery(index, {
    'query': query,
    // One more than shown: the query itself may come back.
    'hitsPerPage':
        math.min(limit, math.max(settings.suggestionCount, 1)) + 1,
    'removeWordsIfNoResults': 'allOptional',
    'attributesToRetrieve': ['query'],
    'attributesToHighlight': <String>[],
    'analyticsTags': ['app', 'no-results'],
  });
}

/// The suggested queries of a [trySuggestionsQuery] answer: distinct, in
/// Algolia's order, never [query] itself, at most [limit].
List<String> trySuggestionsFromResult(
  Map<String, dynamic> result, {
  required String query,
  int limit = 3,
}) {
  final seen = <String>{query.trim().toLowerCase()};
  final out = <String>[];
  for (final hit
      in (result['hits'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()) {
    final text = hit['query'] is String ? (hit['query'] as String).trim() : '';
    if (text.isEmpty || !seen.add(text.toLowerCase())) continue;
    out.add(text);
    if (out.length >= limit) break;
  }
  return out;
}

/// What one results page asks Algolia: the page itself, then — for every
/// facet the shopper filtered on — the same search without that facet's own
/// filter, whose counts keep the facet's other values selectable
/// ("disjunctive faceting", as InstantSearch does it).
class AlgoliaResultsPlan {
  const AlgoliaResultsPlan(this.queries, this.disjunctive);

  final List<AlgoliaQuery> queries;

  /// The attribute each query after the first counts.
  final List<String> disjunctive;
}

/// The facets a results page counts: categories (by id), the price for the
/// slider, and every list facet the admin configured.
List<String> resultFacetAttributes(AlgoliaSettings settings) => [
  kAlgoliaCategoryIds,
  settings.priceAttribute,
  for (final facet in settings.facets)
    if (!facet.isRange && facet.attribute != 'categories') facet.attribute,
];

/// The results page's searches (Figma 09c): [page] is 1-based. A sort other
/// than relevance searches its replica.
AlgoliaResultsPlan resultsQueries(
  AlgoliaSettings settings, {
  required String query,
  String? scopeUid,
  SearchFilters filters = SearchFilters.none,
  SearchSort sort = SearchSort.relevance,
  int page = 1,
  int hitsPerPage = 20,
}) {
  final scopeId = scopeUid == null ? null : categoryIdFromUid(scopeUid);
  final price = settings.priceAttribute;

  List<Object> facetFilters({String? except}) => [
    if (scopeId != null) _facetFilter(kAlgoliaCategoryIds, scopeId),
    for (final MapEntry(key: attribute, value: values)
        in filters.attributes.entries)
      if (attribute != except && values.isNotEmpty)
        [for (final value in values) _facetFilter(attribute, value)],
  ];
  List<String> numericFilters({bool withPrice = true}) => [
    'visibility_search=1',
    if (withPrice && filters.priceFrom != null) '$price>=${filters.priceFrom}',
    if (withPrice && filters.priceTo != null) '$price<=${filters.priceTo}',
    // rating_summary is a percentage: 4★ is 80.
    if (filters.minRating != null) 'rating_summary>=${filters.minRating! * 20}',
  ];

  final index = sort.isRelevance
      ? settings.productsIndex
      : settings.sorts
                .where(
                  (s) =>
                      s.attribute == sort.attribute &&
                      s.descending == sort.descending,
                )
                .firstOrNull
                ?.indexName ??
            settings.productsIndex;
  final main = facetFilters();
  final queries = <AlgoliaQuery>[
    AlgoliaQuery(index, {
      'query': query,
      'page': math.max(page - 1, 0),
      'hitsPerPage': hitsPerPage,
      'facets': resultFacetAttributes(settings),
      'maxValuesPerFacet': _maxValuesPerFacet(settings),
      if (main.isNotEmpty) 'facetFilters': main,
      'numericFilters': numericFilters(),
      'attributesToRetrieve': _productFields,
      'attributesToHighlight': <String>[],
      'analyticsTags': ['app', 'results'],
    }),
  ];

  final disjunctive = <String>[
    for (final MapEntry(key: attribute, value: values)
        in filters.attributes.entries)
      if (values.isNotEmpty) attribute,
    if (filters.hasPrice) price,
  ];
  for (final attribute in disjunctive) {
    final others = facetFilters(except: attribute);
    queries.add(
      AlgoliaQuery(settings.productsIndex, {
        'query': query,
        'page': 0,
        'hitsPerPage': 0,
        'facets': [attribute],
        'maxValuesPerFacet': _maxValuesPerFacet(settings),
        if (others.isNotEmpty) 'facetFilters': others,
        'numericFilters': numericFilters(withPrice: attribute != price),
        'attributesToRetrieve': <String>[],
        'attributesToHighlight': <String>[],
        'analytics': false,
        'clickAnalytics': false,
      }),
    );
  }
  return AlgoliaResultsPlan(queries, disjunctive);
}

/// A results page from [results], the answers to [plan]'s queries.
SearchResultPage resultsFromResponses(
  AlgoliaSettings settings,
  AlgoliaResultsPlan plan,
  List<Map<String, dynamic>> results, {
  required DateTime now,
  String? scopeUid,
  SearchFilters filters = SearchFilters.none,
  SearchSort sort = SearchSort.relevance,
  List<Category> tree = const <Category>[],
  bool sellers = false,
}) {
  final main = results.first;
  final price = settings.priceAttribute;

  // Each facet's counts: its own disjunctive search when it is filtered on,
  // the page's otherwise.
  Object? facetsFor(String attribute) {
    final at = plan.disjunctive.indexOf(attribute);
    return at < 0 ? main['facets'] : results[at + 1]['facets'];
  }

  final priceAt = plan.disjunctive.indexOf(price);
  final priceBounds = facetStats(
    priceAt < 0 ? main['facets_stats'] : results[priceAt + 1]['facets_stats'],
    price,
  );

  final facets = <Aggregation>[
    if (priceBounds != null &&
        settings.facet('price') != null &&
        priceBounds.max > priceBounds.min)
      Aggregation(
        attributeCode: 'price',
        label: settings.facet('price')!.label,
        options: [
          AggregationOption(
            label: '',
            value: '${priceBounds.min.floor()}_${priceBounds.max.ceil()}',
            count: (main['nbHits'] as num?)?.toInt() ?? 0,
          ),
        ],
      ),
    if (settings.facet('categories') != null)
      Aggregation(
        attributeCode: kAlgoliaCategoryIds,
        label: settings.facet('categories')!.label,
        options: [
          for (final category in searchCategoriesFromIds(
            facetCounts(facetsFor(kAlgoliaCategoryIds), kAlgoliaCategoryIds),
            tree,
            excludeUid: scopeUid,
          ))
            AggregationOption(
              label: category.name,
              value: categoryIdFromUid(category.uid) ?? '',
              count: category.count,
            ),
        ],
      ),
    for (final facet in settings.facets)
      if (!facet.isRange && facet.attribute != 'categories')
        Aggregation(
          attributeCode: facet.attribute,
          label: facet.label.isEmpty ? facet.attribute : facet.label,
          options: [
            for (final MapEntry(key: value, value: count) in facetCounts(
              facetsFor(facet.attribute),
              facet.attribute,
            ).entries)
              AggregationOption(label: value, value: value, count: count),
          ],
        ),
  ].where((facet) => facet.options.isNotEmpty).toList(growable: false);

  final page = (main['page'] as num?)?.toInt() ?? 0;
  return SearchResultPage(
    engine: SearchEngine.algolia,
    products: [
      for (final hit
          in (main['hits'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>())
        if (productFromAlgoliaHit(hit, settings, now: now, sellers: sellers)
            case final product?)
          product,
    ],
    totalCount: (main['nbHits'] as num?)?.toInt() ?? 0,
    currentPage: page + 1,
    totalPages: (main['nbPages'] as num?)?.toInt() ?? 0,
    facets: facets,
    categories: searchCategoriesFromIds(
      facetCounts(main['facets'], kAlgoliaCategoryIds),
      tree,
      excludeUid: scopeUid,
    ),
    sorts: [
      const SearchSortOption(SearchSort.relevance),
      for (final replica in settings.sorts)
        SearchSortOption(
          SearchSort(replica.attribute, descending: replica.descending),
          label: replica.label,
        ),
    ],
    sort: sort,
    filters: filters,
    ratingFilter: settings.facet('rating_summary') != null,
  );
}

/// The app's searches against the storefront's Algolia indices — the same
/// indices, settings and ranking as the website's search.
///
/// Every call resolves the active store view's settings first (see
/// [AlgoliaSettingsRepository]) and throws [AlgoliaUnavailable] when Algolia
/// can't answer, for the caller to fall back to GraphQL. A refused key is
/// replaced once from the backend before giving up; after a failure Algolia
/// rests for [pause], so a dead network doesn't hold up every keystroke.
class AlgoliaSearch {
  AlgoliaSearch({
    required this._client,
    required this._settings,
    DateTime Function()? clock,
    this._marketplace = const FixedMarketplaceGate(),
  }) : _clock = clock ?? DateTime.now;

  final AlgoliaClient _client;
  final AlgoliaSettingsRepository _settings;
  final DateTime Function() _clock;

  /// Whether result cards show each record's seller
  /// ([MarketplaceFeatures.listingSellers]).
  final MarketplaceGate _marketplace;

  static const Duration pause = Duration(seconds: 30);
  DateTime? _pausedUntil;

  /// Loads [storeCode]'s settings ahead of the first search.
  Future<void> warmUp(String storeCode) async {
    try {
      await _settings.settingsFor(storeCode);
    } on Object {
      // The first search falls back and tries again later.
    }
  }

  Future<TypeAheadResult> typeAhead({
    required String storeCode,
    required String query,
    String? scopeUid,
    List<Category> tree = const <Category>[],
  }) => _run(storeCode, (settings) async {
    final results = await _client.multiQuery(
      appId: settings.appId,
      apiKey: settings.searchKey,
      queries: typeAheadQueries(settings, query: query, scopeUid: scopeUid),
    );
    return typeAheadFromResults(
      settings,
      results,
      query: query,
      now: _clock(),
      scopeUid: scopeUid,
      tree: tree,
    );
  });

  Future<SearchResultPage> results({
    required String storeCode,
    required String query,
    String? scopeUid,
    SearchFilters filters = SearchFilters.none,
    SearchSort sort = SearchSort.relevance,
    int page = 1,
    int pageSize = 20,
    List<Category> tree = const <Category>[],
  }) => _run(storeCode, (settings) async {
    final plan = resultsQueries(
      settings,
      query: query,
      scopeUid: scopeUid,
      filters: filters,
      sort: sort,
      page: page,
      hitsPerPage: pageSize,
    );
    final results = await _client.multiQuery(
      appId: settings.appId,
      apiKey: settings.searchKey,
      queries: plan.queries,
    );
    return resultsFromResponses(
      settings,
      plan,
      results,
      now: _clock(),
      scopeUid: scopeUid,
      filters: filters,
      sort: sort,
      tree: tree,
      sellers: _marketplace.features.listingSellers,
    );
  });

  /// The "Try" suggestions for [query] (see [trySuggestionsQuery]); empty
  /// when the store has no suggestions index or it can't be read. Never
  /// rests Algolia: a missing suggestions index says nothing about search.
  Future<List<String>> trySuggestions({
    required String storeCode,
    required String query,
    int limit = 3,
  }) async {
    try {
      final settings = await _settings.settingsFor(storeCode);
      final request = trySuggestionsQuery(settings, query: query, limit: limit);
      if (request == null) return const <String>[];
      final results = await _client.multiQuery(
        appId: settings.appId,
        apiKey: settings.searchKey,
        queries: [request],
      );
      return trySuggestionsFromResult(results.first, query: query, limit: limit);
    } on Object {
      return const <String>[];
    }
  }

  Future<T> _run<T>(
    String storeCode,
    Future<T> Function(AlgoliaSettings settings) search,
  ) async {
    final pausedUntil = _pausedUntil;
    if (pausedUntil != null && _clock().isBefore(pausedUntil)) {
      throw const AlgoliaUnavailable('resting after a failure');
    }
    try {
      var settings = await _settings.settingsFor(storeCode);
      try {
        return await search(settings);
      } on AlgoliaException catch (error) {
        if (!error.isKeyRejected || !settings.fromBackend) rethrow;
        // Expired or replaced: read the backend's current key, once.
        await _settings.invalidate(storeCode);
        settings = await _settings.settingsFor(storeCode);
        return await search(settings);
      }
    } on AlgoliaException catch (error) {
      _pausedUntil = _clock().add(pause);
      throw AlgoliaUnavailable('$error');
    } on AlgoliaUnavailable {
      _pausedUntil = _clock().add(pause);
      rethrow;
    }
  }
}

final algoliaSearchProvider = Provider<AlgoliaSearch>((ref) {
  final config = ref.watch(appConfigProvider);
  return AlgoliaSearch(
    client: AlgoliaClient(
      ref.watch(algoliaHttpClientProvider),
      userAgent: config.userAgent,
    ),
    settings: ref.watch(algoliaSettingsRepositoryProvider),
    marketplace: ref.watch(marketplaceGateProvider),
  );
});
