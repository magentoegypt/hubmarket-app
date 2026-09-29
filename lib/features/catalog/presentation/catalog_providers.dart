import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/catalog_repository.dart';
import '../domain/category.dart';
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
