import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/catalog_repository.dart';
import '../data/home_config_provider.dart';
import '../domain/category.dart';
import '../domain/product.dart';
import '../domain/product_detail.dart';

/// Top-level category tree. Refetches when the active store view changes.
final categoryTreeProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  // Kept alive: small, slow-changing, and on the critical path of every home
  // paint — the splash pre-fetches it, and an autoDispose provider would throw
  // that result away the moment the splash's subscription ended. A store switch
  // still invalidates it via the activeStoreCode watch below.
  ref.keepAlive();
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(catalogRepositoryProvider).fetchCategoryTree();
});

/// Resolves a single category (top-level or nested) by uid from the already
/// loaded tree — backs the sub-category drill-down without an extra fetch.
final categoryByUidProvider = FutureProvider.autoDispose
    .family<Category?, String>((ref, uid) async {
      final cats = await ref.watch(categoryTreeProvider.future);
      Category? find(List<Category> list) {
        for (final c in list) {
          if (c.uid == uid) return c;
          final nested = find(c.children);
          if (nested != null) return nested;
        }
        return null;
      }

      return find(cats);
    });

/// Product-image stand-ins for a set of categories, keyed by uid.
///
/// Only top-level categories carry an `image` on this store; sub- and
/// sub-sub-categories come back `null`, which left every tile below the top
/// level showing a placeholder (CL042-DEV22). The storefront fills that gap
/// with the first product inside the category, and so does this.
///
/// The family key is a comma-joined uid list rather than a `List` because
/// Riverpod identifies a family instance by `==`, and two equal lists are not
/// the same object. Kept alive: the result is a handful of URLs per level and
/// re-fetching it on every rebuild would flicker the rail.
final categoryThumbnailsProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, uidKey) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final uids = uidKey.split(',').where((u) => u.isNotEmpty).toList();
      if (uids.isEmpty) return const <String, String>{};
      ref.keepAlive();
      return ref.watch(catalogRepositoryProvider).fetchCategoryThumbnails(uids);
    });

/// Builds the [categoryThumbnailsProvider] key for the categories in [items]
/// that need a stand-in — those with no `image` of their own. Returns an empty
/// string when every one already has an image, so no query is issued.
String categoryThumbnailKey(Iterable<Category> items) => items
    .where((c) => (c.image ?? '').isEmpty)
    .map((c) => c.uid)
    .join(',');

/// Featured products for the home screen — first page of the first category.
final featuredProductsProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final categories = await ref.watch(categoryTreeProvider.future);
  if (categories.isEmpty) return const <Product>[];
  final page = await ref
      .watch(catalogRepositoryProvider)
      .fetchProducts(categoryUid: categories.first.uid, pageSize: 10);
  return page.items;
});

/// A home product section: the source category (for "See all") + its products.
typedef HomeSection = ({Category? category, List<Product> items});

/// How many products a home product rail shows before "See More" — 8 (four
/// rows of the two-column grid), per CL042-DEV09. "Deals of the Day" keeps its
/// own shorter count.
const int _homeSectionSize = 8;

/// Searches the category tree recursively (top-level + nested children) so a
/// target like `new-arrivals`/`bestsellers` is found wherever it sits.
Category? _findCategory(
  List<Category> cats,
  bool Function(String key, String name) test,
) {
  for (final c in cats) {
    if (test(c.urlKey.toLowerCase(), c.name.toLowerCase())) return c;
    final nested = _findCategory(c.children, test);
    if (nested != null) return nested;
  }
  return null;
}

/// "New Arrivals": the latest 8 products from the `new-arrivals` category.
/// Hidden when that category is absent (no fabricated content).
final newArrivalsProvider = FutureProvider.autoDispose<HomeSection>((ref) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final categories = await ref.watch(categoryTreeProvider.future);
  final match = _findCategory(categories, (k, n) => k == 'new-arrivals');
  if (match == null) return (category: null, items: const <Product>[]);
  // The category already holds the newest products in order; created_at sort
  // is unsupported on this store, so take the first page.
  final page = await ref
      .watch(catalogRepositoryProvider)
      .fetchProducts(categoryUid: match.uid, pageSize: _homeSectionSize);
  return (category: match, items: page.items);
});

/// "Bestsellers": products from the `bestsellers` category. Hidden when absent.
final bestsellersProvider = FutureProvider.autoDispose<HomeSection>((ref) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final categories = await ref.watch(categoryTreeProvider.future);
  final match = _findCategory(categories, (k, n) => k == 'bestsellers');
  if (match == null) return (category: null, items: const <Product>[]);
  final page = await ref
      .watch(catalogRepositoryProvider)
      .fetchProducts(categoryUid: match.uid, pageSize: _homeSectionSize);
  return (category: match, items: page.items);
});

/// "Deals of the Day": products from the backend-designated deals category
/// (discounted items carry a real `-X%` badge). The live deals category is
/// flagged out of the menu (`include_in_menu = 0`), so it's resolved by
/// `deals/category_id` from `homeConfigProvider` (uid = base64 of the id) rather
/// than the menu tree; it falls back to a `deals-of-the-day` url_key match if
/// the config id is absent. Hidden when neither resolves. Section visibility is
/// additionally gated on the backend `deals` toggle.
final dealsOfTheDayProvider = FutureProvider.autoDispose<HomeSection>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final config = await ref.watch(homeConfigProvider.future);

  Category? category;
  String? uid;
  if (config.dealsCategoryId.isNotEmpty) {
    // Magento category uid is base64 of the numeric id.
    uid = base64.encode(utf8.encode(config.dealsCategoryId));
  } else {
    final categories = await ref.watch(categoryTreeProvider.future);
    category = _findCategory(categories, (k, n) => k == 'deals-of-the-day');
    uid = category?.uid;
  }
  if (uid == null || uid.isEmpty) {
    return (category: null, items: const <Product>[]);
  }
  final page = await ref
      .watch(catalogRepositoryProvider)
      .fetchProducts(categoryUid: uid, pageSize: 4);
  // Synthesize a minimal category (for the "See More" link) when we resolved
  // by id rather than from the tree.
  category ??= Category(uid: uid, name: '', urlKey: 'deals-of-the-day');
  return (category: category, items: page.items);
});

/// Full product detail for the PDP (by url_key). Refetches on store switch.
final productDetailProvider = FutureProvider.autoDispose
    .family<ProductDetail?, String>((ref, urlKey) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return ref.watch(catalogRepositoryProvider).fetchProductDetail(urlKey);
    });

/// Review rating metadata for the "Write a review" star selector.
final reviewRatingsMetadataProvider =
    FutureProvider.autoDispose<List<ReviewRatingMetadata>>((ref) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return ref.watch(catalogRepositoryProvider).fetchReviewRatingsMetadata();
    });
