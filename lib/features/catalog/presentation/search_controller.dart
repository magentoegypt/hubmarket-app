import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/catalog_repository.dart';
import 'plp_controller.dart';

/// Owns one search query's results — mirrors [PlpController] (paged load,
/// append-on-scroll, aggregation-driven filters + sort) but fetches via
/// `products(search:)` instead of a category. Reuses [PlpState] so the search
/// screen shares the same header/filter UI as the PLP. Reloads on store switch.
class SearchResultsController
    extends AutoDisposeFamilyNotifier<PlpState, String> {
  static const int _pageSize = 20;

  String get _query => arg.trim();

  @override
  PlpState build(String arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    if (_query.isEmpty) return const PlpState();
    Future.microtask(_loadFirst);
    return const PlpState(isLoading: true);
  }

  CatalogRepository get _repo => ref.read(catalogRepositoryProvider);

  Future<void> _loadFirst() async {
    if (_query.isEmpty) return;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.fetchProducts(
        search: _query,
        attributeFilters: state.selectedFilters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
        minDiscount: state.minDiscount,
        minRating: state.minRating,
        sort: state.sort,
        pageSize: _pageSize,
        currentPage: 1,
      );
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
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repo.fetchProducts(
        search: _query,
        attributeFilters: state.selectedFilters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
        minDiscount: state.minDiscount,
        minRating: state.minRating,
        sort: state.sort,
        pageSize: _pageSize,
        currentPage: state.currentPage + 1,
      );
      state = state.copyWith(
        products: [...state.products, ...page.items],
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoadingMore: false,
      );
    } catch (_) {
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
    );
    _loadFirst();
  }

  Future<void> refresh() => _loadFirst();
}

final searchControllerProvider = NotifierProvider.autoDispose
    .family<SearchResultsController, PlpState, String>(
      SearchResultsController.new,
    );
