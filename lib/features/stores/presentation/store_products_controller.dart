import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../catalog/data/catalog_repository.dart' show ProductSortField;
import '../../catalog/presentation/plp_controller.dart';
import '../data/store_products_repository.dart';

/// One seller's product listing (Figma 13), keyed by the seller's numeric id:
/// the PLP's paging, filters and sort ([PlpState]) over `products` filtered by
/// the seller, plus the store's own search field. A new search keeps the
/// filters and sort. Reloads on a store-view switch.
class StoreProductsController extends AutoDisposeFamilyNotifier<PlpState, int> {
  static const int pageSize = 20;

  /// Bumped on every first-page load, so a slow answer to an older search,
  /// filter or sort can't land on top of a newer one.
  int _generation = 0;

  String _search = '';

  /// What the store's search field last searched for; empty for everything.
  String get search => _search;

  @override
  PlpState build(int arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    _generation++;
    Future.microtask(_loadFirst);
    return const PlpState(isLoading: true);
  }

  StoreProductsRepository get _repository =>
      ref.read(storeProductsRepositoryProvider);

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.fetchProducts(
        vendorEntityId: arg,
        search: _search,
        attributeFilters: state.selectedFilters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
        sort: state.sort,
        pageSize: pageSize,
        currentPage: 1,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        products: page.items,
        // A filter that empties the list keeps the sheet's sections, so the
        // filter can be taken back.
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
      final page = await _repository.fetchProducts(
        vendorEntityId: arg,
        search: _search,
        attributeFilters: state.selectedFilters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
        sort: state.sort,
        pageSize: pageSize,
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

  /// Searches the seller's products for [text]; empty lists them all.
  void setSearch(String text) {
    final trimmed = text.trim();
    if (trimmed == _search) return;
    _search = trimmed;
    _restart(state);
  }

  void applyFilters(
    Map<String, Set<String>> filters, {
    double? priceFrom,
    double? priceTo,
  }) => _restart(
    state.copyWith(
      selectedFilters: filters,
      priceFrom: priceFrom,
      priceTo: priceTo,
    ),
  );

  void setSort(ProductSortField sort) {
    if (sort == state.sort) return;
    _restart(state.copyWith(sort: sort));
  }

  Future<void> refresh() => _loadFirst();

  void _restart(PlpState next) {
    state = next.copyWith(
      products: const [],
      currentPage: 0,
      totalPages: 0,
      isLoadingMore: false,
    );
    _loadFirst();
  }
}

final storeProductsControllerProvider = NotifierProvider.autoDispose
    .family<StoreProductsController, PlpState, int>(
      StoreProductsController.new,
    );
