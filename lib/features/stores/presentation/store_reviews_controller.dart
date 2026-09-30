import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/stores_repository.dart';
import '../domain/store_review.dart';

/// A store's Reviews tab (Figma 13), paged.
@immutable
class StoreReviewsState {
  const StoreReviewsState({
    this.rating,
    this.reviewCount = 0,
    this.items = const <StoreReview>[],
    this.totalCount = 0,
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  /// The seller's rating and review count, every store view.
  final double? rating;
  final int reviewCount;

  /// The reviews this store view shows, newest first.
  final List<StoreReview> items;
  final int totalCount;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  static const Object _keep = Object();

  StoreReviewsState copyWith({
    List<StoreReview>? items,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => StoreReviewsState(
    rating: rating,
    reviewCount: reviewCount,
    items: items ?? this.items,
    totalCount: totalCount,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );
}

/// Owns one seller's reviews (by seller code): the first page, then a page
/// more as the tab scrolls. Reloads on a store-view switch — each store view
/// shows its own reviews.
class StoreReviewsController
    extends AutoDisposeFamilyNotifier<StoreReviewsState, String> {
  static const int pageSize = 20;

  int _generation = 0;

  @override
  StoreReviewsState build(String arg) {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    _generation++;
    Future.microtask(_loadFirst);
    return const StoreReviewsState(isLoading: true);
  }

  StoresRepository get _repository => ref.read(storesRepositoryProvider);

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repository.fetchStoreReviews(
        arg,
        pageSize: pageSize,
      );
      if (generation != _generation) return;
      state = page == null
          ? const StoreReviewsState()
          : StoreReviewsState(
              rating: page.rating,
              reviewCount: page.reviewCount,
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
      final page = await _repository.fetchStoreReviews(
        arg,
        pageSize: pageSize,
        currentPage: state.currentPage + 1,
      );
      if (generation != _generation) return;
      final known = {for (final review in state.items) review.id};
      state = state.copyWith(
        items: [
          ...state.items,
          // A review approved between two pages pushes the rest down one.
          for (final review in page?.items ?? const <StoreReview>[])
            if (!known.contains(review.id)) review,
        ],
        currentPage: page?.pageInfo.currentPage ?? state.currentPage,
        totalPages: page?.pageInfo.totalPages ?? state.totalPages,
        isLoadingMore: false,
      );
    } catch (_) {
      if (generation != _generation) return;
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _loadFirst();
}

final storeReviewsControllerProvider = NotifierProvider.autoDispose
    .family<StoreReviewsController, StoreReviewsState, String>(
      StoreReviewsController.new,
    );
