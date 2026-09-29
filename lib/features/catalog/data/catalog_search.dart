import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/category.dart';
import '../domain/search_facets.dart';
import '../domain/search_highlight.dart';
import '../domain/search_results.dart';
import 'algolia/algolia_search.dart';
import 'catalog_repository.dart';

/// The app's catalogue search (QA01: "search behaves like the website").
///
/// It asks the storefront's Algolia indices first — the website's engine,
/// settings and ranking ([AlgoliaSearch]) — and falls back to Magento GraphQL
/// `products(search:)` whenever Algolia can't answer (no settings, offline,
/// a refused key, an unexpected answer), so search never breaks. GraphQL is
/// answered from OpenSearch on Hub Market, so its ranking can differ; the
/// result says which engine answered ([SearchEngine]), and only an Algolia
/// answer carries the "Search by algolia" attribution.
class CatalogSearch {
  CatalogSearch({required this._algolia, required this._catalog});

  final AlgoliaSearch _algolia;
  final CatalogRepository _catalog;

  /// Product rows of a GraphQL type-ahead (Algolia's come from the admin's
  /// autocomplete settings).
  static const int fallbackTypeAheadProducts = 8;

  /// Category chips of a GraphQL type-ahead.
  static const int fallbackCategoryChips = 5;

  /// The sorts GraphQL `products` can apply to a search.
  static const List<SearchSortOption> catalogSorts = <SearchSortOption>[
    SearchSortOption(SearchSort.relevance),
    SearchSortOption(SearchSort('price')),
    SearchSortOption(SearchSort('price', descending: true)),
    SearchSortOption(SearchSort('name')),
  ];

  /// Gets the store view's Algolia settings ready before the first search.
  Future<void> warmUp(String storeCode) => _algolia.warmUp(storeCode);

  /// The type-ahead's answer (Figma 09) for [query], optionally within the
  /// category [scopeUid]. [tree] names the categories the matches fall into.
  Future<TypeAheadResult> typeAhead({
    required String storeCode,
    required String query,
    String? scopeUid,
    List<Category> tree = const <Category>[],
  }) async {
    try {
      return await _algolia.typeAhead(
        storeCode: storeCode,
        query: query,
        scopeUid: scopeUid,
        tree: tree,
      );
    } on Object catch (error) {
      _noteFallback(error);
    }

    final page = await _catalog.fetchProducts(
      search: query,
      categoryUid: scopeUid,
      pageSize: 20,
      currentPage: 1,
    );
    final categories = searchCategoriesFrom(
      aggregations: page.aggregations,
      products: page.items,
      tree: tree,
      excludeUid: scopeUid,
    );
    return TypeAheadResult(
      engine: SearchEngine.catalog,
      products: [
        for (final product in page.items.take(fallbackTypeAheadProducts))
          SearchProductHit(
            product: product,
            nameMatches: searchMatchSlices(product.name, query),
            categoryName: product.primaryCategory?.name,
          ),
      ],
      totalCount: page.totalCount,
      resultCategories: categories,
      categoryChips: categories
          .take(fallbackCategoryChips)
          .toList(growable: false),
    );
  }

  /// A page of full results (Figma 09c). [page] is 1-based.
  ///
  /// [engine] pins the engine that answered the earlier pages, so paging and
  /// filters stay on one index. Unpinned, Algolia is tried first; when the
  /// answer then comes from GraphQL, filters and a sort chosen from Algolia's
  /// facets and replicas can't carry over and are dropped.
  Future<SearchResultPage> results({
    required String storeCode,
    required String query,
    String? scopeUid,
    SearchFilters filters = SearchFilters.none,
    SearchSort sort = SearchSort.relevance,
    int page = 1,
    int pageSize = 20,
    SearchEngine? engine,
    List<Category> tree = const <Category>[],
  }) async {
    if (engine != SearchEngine.catalog) {
      try {
        return await _algolia.results(
          storeCode: storeCode,
          query: query,
          scopeUid: scopeUid,
          filters: filters,
          sort: sort,
          page: page,
          pageSize: pageSize,
          tree: tree,
        );
      } on Object catch (error) {
        // More pages of an Algolia list can't come from another engine.
        if (engine == SearchEngine.algolia && page > 1) rethrow;
        _noteFallback(error);
      }
    }

    final carried = engine == SearchEngine.catalog;
    final keptFilters = carried ? filters : SearchFilters.none;
    final keptSort = catalogSorts.any((option) => option.sort == sort)
        ? sort
        : SearchSort.relevance;
    final result = await _catalog.fetchProducts(
      search: query,
      categoryUid: scopeUid,
      attributeFilters: keptFilters.attributes,
      priceFrom: keptFilters.priceFrom,
      priceTo: keptFilters.priceTo,
      sort: _productSort(keptSort),
      pageSize: pageSize,
      currentPage: page,
    );
    return SearchResultPage(
      engine: SearchEngine.catalog,
      products: result.items,
      totalCount: result.totalCount,
      currentPage: result.currentPage,
      totalPages: result.totalPages,
      facets: result.aggregations,
      categories: searchCategoriesFrom(
        aggregations: result.aggregations,
        products: result.items,
        tree: tree,
        excludeUid: scopeUid,
      ),
      sorts: catalogSorts,
      sort: keptSort,
      filters: keptFilters,
      ratingFilter: kRatingFilterSupported,
    );
  }

  static ProductSortField _productSort(SearchSort sort) =>
      switch ((sort.attribute, sort.descending)) {
        ('price', false) => ProductSortField.priceAsc,
        ('price', true) => ProductSortField.priceDesc,
        ('name', false) => ProductSortField.nameAsc,
        _ => ProductSortField.relevance,
      };

  static void _noteFallback(Object error) {
    // The reason only — requests and keys are never printed.
    if (kDebugMode) debugPrint('Search falls back to GraphQL: $error');
  }
}

final catalogSearchProvider = Provider<CatalogSearch>(
  (ref) => CatalogSearch(
    algolia: ref.watch(algoliaSearchProvider),
    catalog: ref.watch(catalogRepositoryProvider),
  ),
);
