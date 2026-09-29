import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/catalog_repository.dart';
import 'plp_controller.dart';

/// What one search asks for: the text, and optionally the top-level category
/// the type-ahead's "All categories" chip narrowed it to. Keys
/// [searchControllerProvider], so the type-ahead and the full results share one
/// load — "View all N results" opens on data that is already there.
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

/// Owns one search's results — mirrors [PlpController] (paged load,
/// append-on-scroll, aggregation-driven filters + sort) but fetches via
/// `products(search:)` instead of a category. Reuses [PlpState] so the search
/// screen shares the same filter/sort sheets as the PLP. Reloads on store
/// switch.
class SearchResultsController
    extends AutoDisposeFamilyNotifier<PlpState, SearchRequest> {
  static const int _pageSize = 20;

  /// Bumped on every first-page load, so a slow answer to an older filter or
  /// sort can't land on top of a newer one.
  int _generation = 0;

  String get _query => arg.query.trim();

  @override
  PlpState build(SearchRequest arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    _generation++;
    if (_query.isEmpty) return const PlpState();
    Future.microtask(_loadFirst);
    return const PlpState(isLoading: true);
  }

  CatalogRepository get _repo => ref.read(catalogRepositoryProvider);

  Future<void> _loadFirst() async {
    if (_query.isEmpty) return;
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.fetchProducts(
        search: _query,
        categoryUid: arg.categoryUid,
        attributeFilters: state.selectedFilters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
        minDiscount: state.minDiscount,
        minRating: state.minRating,
        sort: state.sort,
        pageSize: _pageSize,
        currentPage: 1,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        products: page.items,
        aggregations: page.aggregations.isNotEmpty
            ? page.aggregations
            : state.aggregations,
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
      final page = await _repo.fetchProducts(
        search: _query,
        categoryUid: arg.categoryUid,
        attributeFilters: state.selectedFilters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
        minDiscount: state.minDiscount,
        minRating: state.minRating,
        sort: state.sort,
        pageSize: _pageSize,
        currentPage: state.currentPage + 1,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        products: [...state.products, ...page.items],
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

  void applyFilters(
    Map<String, Set<String>> filters, {
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField? sort,
  }) {
    state = state.copyWith(
      selectedFilters: filters,
      priceFrom: priceFrom,
      priceTo: priceTo,
      minDiscount: minDiscount,
      minRating: minRating,
      sort: sort ?? state.sort,
      products: const [],
      currentPage: 0,
      totalPages: 0,
      isLoadingMore: false,
    );
    _loadFirst();
  }

  void setSort(ProductSortField sort) {
    if (sort == state.sort) return;
    state = state.copyWith(
      sort: sort,
      products: const [],
      currentPage: 0,
      totalPages: 0,
      isLoadingMore: false,
    );
    _loadFirst();
  }

  Future<void> refresh() => _loadFirst();
}

final searchControllerProvider = NotifierProvider.autoDispose
    .family<SearchResultsController, PlpState, SearchRequest>(
      SearchResultsController.new,
    );
