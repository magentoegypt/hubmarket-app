import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/reviews_repository.dart';
import '../domain/product_detail.dart';
import '../domain/review_pages.dart';

/// Reviews are loaded in pages of this size — Magento's own default.
const int kReviewsPageSize = 20;

/// The Reviews screen (Figma 15): a product's published reviews, paged.
class ProductReviewsState {
  const ProductReviewsState({
    this.product,
    this.reviews = const <ProductReview>[],
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.notFound = false,
    this.error,
  });

  /// The first page as loaded — its sku, name and review totals.
  final ProductReviewsPage? product;
  final List<ProductReview> reviews;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final bool notFound;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  /// Per-star bars, exact or not at all: counted only once every published
  /// review is loaded (see [RatingBar.exactHistogram]).
  List<RatingBar> get histogram => hasMore
      ? const <RatingBar>[]
      : RatingBar.exactHistogram(reviews, product?.reviewCount ?? 0);

  ProductReviewsState copyWith({
    ProductReviewsPage? product,
    List<ProductReview>? reviews,
    int? currentPage,
    int? totalPages,
    bool? isLoading,
    bool? isLoadingMore,
    bool? notFound,
    Object? error = _keep,
  }) => ProductReviewsState(
    product: product ?? this.product,
    reviews: reviews ?? this.reviews,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    notFound: notFound ?? this.notFound,
    error: identical(error, _keep) ? this.error : error,
  );

  static const Object _keep = Object();
}

/// Pages through the reviews of the product with the family's url key.
class ProductReviewsController
    extends AutoDisposeFamilyNotifier<ProductReviewsState, String> {
  @override
  ProductReviewsState build(String urlKey) {
    // Reviews are per store view: reload on a language switch.
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next) Future.microtask(refresh);
      },
    );
    Future.microtask(refresh);
    return const ProductReviewsState();
  }

  ReviewsRepository get _repo => ref.read(reviewsRepositoryProvider);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await _repo.fetchProductReviews(
        arg,
        pageSize: kReviewsPageSize,
      );
      if (page == null) {
        state = const ProductReviewsState(isLoading: false, notFound: true);
        return;
      }
      state = ProductReviewsState(
        product: page,
        reviews: page.reviews,
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
      final page = await _repo.fetchProductReviews(
        arg,
        pageSize: kReviewsPageSize,
        currentPage: state.currentPage + 1,
      );
      state = state.copyWith(
        reviews: [...state.reviews, ...?page?.reviews],
        currentPage: page?.currentPage ?? state.totalPages,
        totalPages: page?.totalPages ?? state.totalPages,
        isLoadingMore: false,
      );
    } catch (_) {
      // Keep what is shown; scrolling to the end again retries.
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final productReviewsControllerProvider = NotifierProvider.autoDispose
    .family<ProductReviewsController, ProductReviewsState, String>(
      ProductReviewsController.new,
    );

/// My product reviews (Figma 20f).
class MyReviewsState {
  const MyReviewsState({
    this.items = const <CustomerReview>[],
    this.currentPage = 0,
    this.totalPages = 0,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<CustomerReview> items;
  final int currentPage;
  final int totalPages;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  /// How many reviews the customer has written — known exactly only once
  /// every page is in (`ProductReviews` carries no total count); null before.
  int? get count => (!isLoading && !hasMore) ? items.length : null;
}

class MyReviewsController extends AutoDisposeNotifier<MyReviewsState> {
  @override
  MyReviewsState build() {
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next) Future.microtask(refresh);
      },
    );
    if (!signedIn) return const MyReviewsState(isLoading: false);
    Future.microtask(refresh);
    return const MyReviewsState();
  }

  ReviewsRepository get _repo => ref.read(reviewsRepositoryProvider);

  Future<void> refresh() async {
    if (!ref.read(authControllerProvider).isAuthenticated) return;
    state = MyReviewsState(items: state.items);
    try {
      final page = await _repo.fetchCustomerReviews(
        pageSize: kReviewsPageSize,
      );
      state = MyReviewsState(
        items: page.items,
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        isLoading: false,
      );
    } catch (error) {
      state = MyReviewsState(items: state.items, isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.isLoading || s.isLoadingMore || !s.hasMore) return;
    state = MyReviewsState(
      items: s.items,
      currentPage: s.currentPage,
      totalPages: s.totalPages,
      isLoading: false,
      isLoadingMore: true,
    );
    try {
      final page = await _repo.fetchCustomerReviews(
        pageSize: kReviewsPageSize,
        currentPage: s.currentPage + 1,
      );
      state = MyReviewsState(
        items: [...s.items, ...page.items],
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        isLoading: false,
      );
    } catch (_) {
      state = MyReviewsState(
        items: s.items,
        currentPage: s.currentPage,
        totalPages: s.totalPages,
        isLoading: false,
      );
    }
  }
}

final myReviewsControllerProvider =
    AutoDisposeNotifierProvider<MyReviewsController, MyReviewsState>(
      MyReviewsController.new,
    );
