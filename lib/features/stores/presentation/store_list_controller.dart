import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../data/stores_repository.dart';
import '../domain/store.dart';

/// A paged seller list (Figma 12's "All stores").
@immutable
class StoreListState {
  const StoreListState({
    this.items = const <HmStoreCard>[],
    this.totalCount = 0,
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<HmStoreCard> items;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  static const Object _keep = Object();

  StoreListState copyWith({
    List<HmStoreCard>? items,
    int? totalCount,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => StoreListState(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Owns one [StoreListQuery]'s list: the first page, then a page more as the
/// list scrolls. A new filter, search or sort is a new query (a new family
/// member), so each starts from the top. Reloads on a store-view switch.
class StoreListController
    extends AutoDisposeFamilyNotifier<StoreListState, StoreListQuery> {
  static const int pageSize = 20;

  /// Bumped on every first-page load, so a slow answer can't land on top of a
  /// newer one.
  int _generation = 0;

  @override
  StoreListState build(StoreListQuery arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    _generation++;
    Future.microtask(_loadFirst);
    return const StoreListState(isLoading: true);
  }

  StoresRepository get _repository => ref.read(storesRepositoryProvider);

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.fetchStores(
        query: arg,
        pageSize: pageSize,
        currentPage: 1,
      );
      if (generation != _generation) return;
      state = StoreListState(
        items: page.items,
        totalCount: page.totalCount,
        currentPage: page.pageInfo.currentPage,
        totalPages: page.pageInfo.totalPages,
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
      final page = await _repository.fetchStores(
        query: arg,
        pageSize: pageSize,
        currentPage: state.currentPage + 1,
      );
      if (generation != _generation) return;
      final known = {for (final card in state.items) card.code};
      state = state.copyWith(
        items: [
          ...state.items,
          // A seller that moved up a page between requests isn't listed twice.
          for (final card in page.items)
            if (!known.contains(card.code)) card,
        ],
        totalCount: page.totalCount,
        currentPage: page.pageInfo.currentPage,
        totalPages: page.pageInfo.totalPages,
        isLoadingMore: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _loadFirst();
}

final storeListControllerProvider = NotifierProvider.autoDispose
    .family<StoreListController, StoreListState, StoreListQuery>(
      StoreListController.new,
    );
