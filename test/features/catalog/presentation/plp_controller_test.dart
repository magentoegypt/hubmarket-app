import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/product_page.dart';
import 'package:hubmarket_app/features/catalog/presentation/plp_controller.dart';

import '../../../support/fakes.dart';

ProviderContainer _container(CatalogRepository repo) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      catalogRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('PlpController', () {
    test('first load populates products and aggregations', () async {
      final container = _container(FakeCatalogRepository());
      final notifier = container.read(plpControllerProvider('cat').notifier);
      await notifier.refresh();

      final state = container.read(plpControllerProvider('cat'));
      expect(state.isLoading, isFalse);
      expect(state.products, isNotEmpty);
      expect(state.aggregations, isNotEmpty);
    });

    test('applyFilters records the selection', () async {
      final container = _container(FakeCatalogRepository());
      final notifier = container.read(plpControllerProvider('cat').notifier);
      await notifier.refresh();

      notifier.applyFilters({
        'brand': {'101'},
      });
      await notifier.refresh();

      final state = container.read(plpControllerProvider('cat'));
      expect(state.selectedFilters['brand'], contains('101'));
      expect(state.activeFilterCount, 1);
    });

    test('loadMore appends the next page', () async {
      final container = _container(_PagingRepo());
      final notifier = container.read(plpControllerProvider('cat').notifier);
      await notifier.refresh();
      expect(
        container.read(plpControllerProvider('cat')).products,
        hasLength(1),
      );
      expect(container.read(plpControllerProvider('cat')).hasMore, isTrue);

      await notifier.loadMore();
      final state = container.read(plpControllerProvider('cat'));
      expect(state.products, hasLength(2));
      expect(state.hasMore, isFalse);
    });
  });
}

/// Returns a distinct single item per page across two pages.
class _PagingRepo implements CatalogRepository {
  @override
  Future<List<Category>> fetchCategoryTree() async => kSampleCategories;

  @override
  Future<Map<String, String>> fetchCategoryThumbnails(
    List<String> categoryUids,
  ) async => const <String, String>{};

  @override
  Future<({String type, String uid, String? urlKey})?> resolveUrl(
    String storeUrl,
  ) async => null;

  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async =>
      kSampleDetail;

  @override
  Future<ProductPage> fetchProducts({
    String? search,
    String? categoryUid,
    int? brandOptionId,
    Map<String, Set<String>> attributeFilters = const {},
    double? priceFrom,
    double? priceTo,
    int? minDiscount,
    int? minRating,
    ProductSortField sort = ProductSortField.relevance,
    int pageSize = 20,
    int currentPage = 1,
  }) async => ProductPage(
    items: [
      Product(
        sku: 'p$currentPage',
        name: 'Product $currentPage',
        urlKey: 'p$currentPage',
      ),
    ],
    totalCount: 2,
    currentPage: currentPage,
    totalPages: 2,
  );

  @override
  Future<List<ReviewRatingMetadata>> fetchReviewRatingsMetadata() async =>
      const [];

  @override
  Future<void> createReview({
    required String sku,
    required String nickname,
    required String summary,
    required String text,
    required List<({String id, String valueId})> ratings,
  }) async {}
}
