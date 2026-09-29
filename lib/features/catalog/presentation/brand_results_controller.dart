import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/catalog_repository.dart';
import 'plp_controller.dart';

/// Owns one brand landing's products — mirrors [SearchResultsController] (paged
/// load, append-on-scroll, aggregation-driven filters + sort) but fetches by the
/// brand's `manufacturer` attribute option id instead of a text search. This is
/// the real "Shop by Brand" product set: `products(search: "<brand name>")`
/// returns cross-brand matches, whereas `manufacturer: {eq: <optionId>}` returns
/// exactly that brand's products (matching the website's /shopbrand/ page).
/// Reuses [PlpState] so the brand landing shares the PLP/search header + filter
/// UI. Keyed by the brand option id; reloads on store switch.
class BrandResultsController
    extends AutoDisposeFamilyNotifier<PlpState, int> {
  static const int _pageSize = 20;

  int get _manufacturerId => arg;

  @override
  PlpState build(int arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    Future.microtask(_loadFirst);
    return const PlpState(isLoading: true);
  }

  CatalogRepository get _repo => ref.read(catalogRepositoryProvider);

  Future<void> _loadFirst() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.fetchProducts(
        manufacturerId: _manufacturerId,
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
        manufacturerId: _manufacturerId,
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

final brandResultsControllerProvider = NotifierProvider.autoDispose
    .family<BrandResultsController, PlpState, int>(
      BrandResultsController.new,
    );
