import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../../core/store/store_controller.dart';
import '../../catalog/domain/product.dart';
import '../data/deals_repository.dart';
import '../domain/deals.dart';

@immutable
class DealsState {
  const DealsState({
    this.items = const <Product>[],
    this.totalCount = 0,
    this.countdownEndsAt,
    this.categories = const <DealCategory>[],
    this.filters = const DealsFilters(),
    this.filtersSupported = true,
    this.pageInfo = const HmPageInfo(),
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  /// The deals loaded so far, in the server's order for [filters].
  final List<Product> items;

  /// Deals matching [filters].
  final int totalCount;
  final DateTime? countdownEndsAt;

  /// Department chips from the server: they count every filter but the
  /// category, so they stay while one is selected.
  final List<DealCategory> categories;
  final DealsFilters filters;

  /// False when the server is a HubApp older than the filters: the list is
  /// the plain ranking and the screen offers no chips, sort or filters.
  final bool filtersSupported;
  final HmPageInfo pageInfo;
  final bool isLoading;
  final bool isLoadingMore;

  /// Set when the first page failed.
  final Object? error;

  bool get hasMore => pageInfo.hasMore;

  DealsState copyWith({
    List<Product>? items,
    int? totalCount,
    DateTime? countdownEndsAt,
    List<DealCategory>? categories,
    DealsFilters? filters,
    bool? filtersSupported,
    HmPageInfo? pageInfo,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => DealsState(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    countdownEndsAt: countdownEndsAt ?? this.countdownEndsAt,
    categories: categories ?? this.categories,
    filters: filters ?? this.filters,
    filtersSupported: filtersSupported ?? this.filtersSupported,
    pageInfo: pageInfo ?? this.pageInfo,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );

  static const Object _keep = Object();
}

/// Today's Deals (10b, `hmDeals`): pages of 20 as the list scrolls, filtered
/// and sorted on the server over the day's whole ranking — a department
/// chip, a minimum discount and five orders — so nothing is worked out on a
/// partial list.
class DealsController extends AutoDisposeNotifier<DealsState> {
  static const int pageSize = 20;

  int _generation = 0;

  @override
  DealsState build() {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    Future.microtask(_loadFirst);
    return const DealsState();
  }

  DealsRepository get _repository => ref.read(dealsRepositoryProvider);

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    final filters = state.filters;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.fetchDeals(
        pageSize: pageSize,
        filters: filters,
      );
      if (generation != _generation) return;
      state = DealsState(
        items: page.items,
        totalCount: page.totalCount,
        countdownEndsAt: page.countdownEndsAt,
        categories: page.categories,
        filters: filters,
        filtersSupported: page.filtered,
        pageInfo: page.pageInfo,
        isLoading: false,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  /// The next page, when the list nears its end.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    final generation = _generation;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await _repository.fetchDeals(
        pageSize: pageSize,
        currentPage: state.pageInfo.currentPage + 1,
        filters: state.filters,
      );
      if (generation != _generation) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        pageInfo: page.pageInfo,
        isLoadingMore: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      // What arrived stays; scrolling tries again.
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _loadFirst();

  /// Reads the list again under [filters] (a chip, the sort, the sheet).
  void apply(DealsFilters filters) {
    if (filters == state.filters) return;
    state = state.copyWith(filters: filters, items: const <Product>[]);
    unawaited(_loadFirst());
  }

  void selectCategory(int? id) =>
      apply(state.filters.copyWith(categoryId: id));

  void setSort(DealsSort sort) => apply(state.filters.copyWith(sort: sort));
}

final dealsControllerProvider =
    NotifierProvider.autoDispose<DealsController, DealsState>(
      DealsController.new,
    );
