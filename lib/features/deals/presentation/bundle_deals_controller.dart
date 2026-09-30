import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/deals_repository.dart';
import '../domain/deals.dart';

@immutable
class BundleDealsState {
  const BundleDealsState({
    this.page = BundleDealPage.empty,
    this.items = const <BundleDeal>[],
    this.categories = const <DealCategory>[],
    this.categoryId,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  /// The last page read (its stats and paging).
  final BundleDealPage page;

  /// Every card loaded so far for [categoryId].
  final List<BundleDeal> items;

  /// The chips of the unfiltered list — they stay while one is selected.
  final List<DealCategory> categories;

  /// The selected chip; null is "All bundles".
  final int? categoryId;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => page.pageInfo.hasMore;

  BundleDealsState copyWith({
    BundleDealPage? page,
    List<BundleDeal>? items,
    List<DealCategory>? categories,
    Object? categoryId = _keep,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => BundleDealsState(
    page: page ?? this.page,
    items: items ?? this.items,
    categories: categories ?? this.categories,
    categoryId: identical(categoryId, _keep)
        ? this.categoryId
        : categoryId as int?,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );

  static const Object _keep = Object();
}

/// Bundle deals (10c, `hmBundleDeals`): pages of 20, filtered on the server
/// by top-level category.
class BundleDealsController extends AutoDisposeNotifier<BundleDealsState> {
  static const int pageSize = 20;

  int _generation = 0;

  @override
  BundleDealsState build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    Future.microtask(_loadFirst);
    return const BundleDealsState();
  }

  DealsRepository get _repository => ref.read(dealsRepositoryProvider);

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    final categoryId = state.categoryId;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.fetchBundleDeals(
        categoryId: categoryId,
        pageSize: pageSize,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        page: page,
        items: page.items,
        categories: categoryId == null ? page.categories : null,
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
      final page = await _repository.fetchBundleDeals(
        categoryId: state.categoryId,
        pageSize: pageSize,
        currentPage: state.page.pageInfo.currentPage + 1,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        page: page,
        items: [...state.items, ...page.items],
        isLoadingMore: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void selectCategory(int? id) {
    if (id == state.categoryId) return;
    state = state.copyWith(categoryId: id, items: const <BundleDeal>[]);
    unawaited(_loadFirst());
  }

  Future<void> refresh() => _loadFirst();
}

final bundleDealsControllerProvider =
    NotifierProvider.autoDispose<BundleDealsController, BundleDealsState>(
      BundleDealsController.new,
    );
