import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../catalog/data/best_sellers_repository.dart';
import '../../catalog/domain/product.dart';

@immutable
class BestSellersState {
  const BestSellersState({
    this.items = const <Product>[],
    this.totalCount = 0,
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  /// Every best seller loaded so far, in rank order.
  final List<Product> items;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;

  /// Set when the first page failed.
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  BestSellersState copyWith({
    List<Product>? items,
    int? totalCount,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => BestSellersState(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );

  static const Object _keep = Object();
}

/// Best sellers (`hmBestSellers`), a page at a time as the list scrolls.
/// Reloads on a store-view switch: names and prices are per language.
class BestSellersController extends AutoDisposeNotifier<BestSellersState> {
  static const int pageSize = 20;

  int _generation = 0;

  @override
  BestSellersState build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    Future.microtask(_loadFirst);
    return const BestSellersState();
  }

  BestSellersRepository get _repository =>
      ref.read(bestSellersRepositoryProvider);

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.fetchPage(pageSize: pageSize);
      if (generation != _generation) return;
      state = BestSellersState(
        items: page.items,
        totalCount: page.totalCount,
        currentPage: 1,
        totalPages: page.items.isEmpty ? 1 : page.pageInfo.totalPages,
        isLoading: false,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  /// The next page; a failure leaves what is shown, and the next scroll tries
  /// again.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final generation = _generation;
    final next = state.currentPage + 1;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repository.fetchPage(
        pageSize: pageSize,
        currentPage: next,
      );
      if (generation != _generation) return;
      // The ranking can shift between pages: a product shows once.
      final seen = {for (final p in state.items) p.urlKey};
      state = state.copyWith(
        items: [
          ...state.items,
          for (final p in page.items)
            if (seen.add(p.urlKey)) p,
        ],
        currentPage: next,
        // An empty page ends the list whatever the paging says.
        totalPages: page.items.isEmpty ? next : page.pageInfo.totalPages,
        isLoadingMore: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _loadFirst();
}

final bestSellersControllerProvider =
    NotifierProvider.autoDispose<BestSellersController, BestSellersState>(
      BestSellersController.new,
    );
