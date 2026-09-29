import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/catalog_search.dart';
import '../domain/aggregation.dart';
import '../domain/category.dart';
import '../domain/product.dart';
import '../domain/search_facets.dart';
import '../domain/search_results.dart';
import 'catalog_providers.dart';

/// What one search asks for: the text, and optionally the top-level category
/// the type-ahead's "All categories" chip narrowed it to. Keys
/// [typeAheadProvider] and [searchResultsProvider].
@immutable
class SearchRequest {
  const SearchRequest(this.query, {this.categoryUid});

  final String query;
  final String? categoryUid;

  @override
  bool operator ==(Object other) =>
      other is SearchRequest &&
      other.query == query &&
      other.categoryUid == categoryUid;

  @override
  int get hashCode => Object.hash(query, categoryUid);
}

/// The category tree for naming the categories results fall into; empty when
/// it can't load — search still works, it just can't name them.
Future<List<Category>> _treeFor(Ref ref) async {
  try {
    return await ref.watch(categoryTreeProvider.future);
  } on Object {
    return const <Category>[];
  }
}

/// The type-ahead's answer (Figma 09) for one debounced query: Algolia's
/// products, category and page suggestions, or the GraphQL fallback's.
/// Reloads on a store switch — the language picks the indices.
final typeAheadProvider = FutureProvider.autoDispose
    .family<TypeAheadResult, SearchRequest>((ref, request) async {
      final storeCode = ref.watch(
        storeControllerProvider.select((s) => s.activeStoreCode),
      );
      final search = ref.watch(catalogSearchProvider);
      final tree = await _treeFor(ref);
      return search.typeAhead(
        storeCode: storeCode,
        query: request.query.trim(),
        scopeUid: request.categoryUid,
        tree: tree,
      );
    });

/// A submitted search's full results (Figma 09c).
@immutable
class SearchResultsState {
  const SearchResultsState({
    this.engine,
    this.products = const <Product>[],
    this.facets = const <Aggregation>[],
    this.categories = const <SearchCategory>[],
    this.sorts = const <SearchSortOption>[],
    this.sort = SearchSort.relevance,
    this.filters = SearchFilters.none,
    this.ratingFilter = false,
    this.totalCount = 0,
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  /// Which engine answered — null until the first page arrives.
  final SearchEngine? engine;
  final List<Product> products;

  /// The Filter sheet's sections.
  final List<Aggregation> facets;

  /// The Categories tab.
  final List<SearchCategory> categories;

  /// The Sort sheet's options, relevance first.
  final List<SearchSortOption> sorts;
  final SearchSort sort;
  final SearchFilters filters;

  /// Whether the Filter sheet offers "N★ & above".
  final bool ratingFilter;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  static const Object _keep = Object();

  SearchResultsState copyWith({
    SearchEngine? engine,
    List<Product>? products,
    List<Aggregation>? facets,
    List<SearchCategory>? categories,
    List<SearchSortOption>? sorts,
    SearchSort? sort,
    SearchFilters? filters,
    bool? ratingFilter,
    int? totalCount,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => SearchResultsState(
    engine: engine ?? this.engine,
    products: products ?? this.products,
    facets: facets ?? this.facets,
    categories: categories ?? this.categories,
    sorts: sorts ?? this.sorts,
    sort: sort ?? this.sort,
    filters: filters ?? this.filters,
    ratingFilter: ratingFilter ?? this.ratingFilter,
    totalCount: totalCount ?? this.totalCount,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Owns one submitted search's results: Algolia pages (its paging, its
/// replicas for sorting, its facets for filtering), or the GraphQL fallback's
/// when Algolia can't answer — see [CatalogSearch]. Later pages, filters and
/// sorts stay on the engine that answered the first page. Reloads on a store
/// switch.
class SearchResultsController
    extends AutoDisposeFamilyNotifier<SearchResultsState, SearchRequest> {
  static const int pageSize = 20;

  /// Bumped on every first-page load, so a slow answer to an older filter or
  /// sort can't land on top of a newer one.
  int _generation = 0;

  String get _query => arg.query.trim();

  @override
  SearchResultsState build(SearchRequest arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    _generation++;
    if (arg.query.trim().isEmpty) return const SearchResultsState();
    Future.microtask(_loadFirst);
    return const SearchResultsState(isLoading: true);
  }

  CatalogSearch get _search => ref.read(catalogSearchProvider);
  String get _storeCode => ref.read(storeControllerProvider).activeStoreCode;

  Future<List<Category>> _tree() async {
    try {
      return await ref.read(categoryTreeProvider.future);
    } on Object {
      return const <Category>[];
    }
  }

  Future<void> _loadFirst() async {
    if (_query.isEmpty) return;
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _search.results(
        storeCode: _storeCode,
        query: _query,
        scopeUid: arg.categoryUid,
        filters: state.filters,
        sort: state.sort,
        page: 1,
        pageSize: pageSize,
        engine: state.engine,
        tree: await _tree(),
      );
      if (generation != _generation) return;
      state = state.copyWith(
        engine: page.engine,
        products: page.products,
        // A filter that empties the list keeps the sheet's sections, so the
        // filter can be taken back.
        facets: page.facets.isNotEmpty || page.engine != state.engine
            ? page.facets
            : state.facets,
        categories: page.categories,
        sorts: page.sorts,
        sort: page.sort,
        filters: page.filters,
        ratingFilter: page.ratingFilter,
        totalCount: page.totalCount,
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        isLoading: false,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _search.results(
        storeCode: _storeCode,
        query: _query,
        scopeUid: arg.categoryUid,
        filters: state.filters,
        sort: state.sort,
        page: state.currentPage + 1,
        pageSize: pageSize,
        engine: state.engine,
        tree: await _tree(),
      );
      if (generation != _generation) return;
      state = state.copyWith(
        products: [...state.products, ...page.products],
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoadingMore: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void applyFilters(SearchFilters filters) {
    state = state.copyWith(
      filters: filters,
      products: const <Product>[],
      currentPage: 0,
      totalPages: 0,
      isLoadingMore: false,
    );
    _loadFirst();
  }

  void setSort(SearchSort sort) {
    if (sort == state.sort) return;
    state = state.copyWith(
      sort: sort,
      products: const <Product>[],
      currentPage: 0,
      totalPages: 0,
      isLoadingMore: false,
    );
    _loadFirst();
  }

  Future<void> refresh() => _loadFirst();
}

final searchResultsProvider = NotifierProvider.autoDispose
    .family<SearchResultsController, SearchResultsState, SearchRequest>(
      SearchResultsController.new,
    );
