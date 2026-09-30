import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../marketplace/domain/product_offer.dart';
import '../../marketplace/marketplace_features.dart';
import '../../marketplace/product_offers.dart';
import '../data/catalog_repository.dart';
import '../data/product_marketplace_repository.dart';
import '../data/product_route_query.dart';
import '../domain/category.dart';
import '../domain/product_detail.dart';
import '../domain/product_marketplace.dart';

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
///
/// With the Hub Market App, a url_key product search doesn't know is looked
/// up once more by its URL: another seller's offer, opened from "Sold by N
/// other sellers", is a product of its own that search leaves out. Build 1
/// asks exactly what it did.
final productDetailProvider = FutureProvider.autoDispose
    .family<ProductDetail?, String>((ref, urlKey) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final detail = await ref
          .watch(catalogRepositoryProvider)
          .fetchProductDetail(urlKey);
      if (detail != null ||
          ref.read(hubAppStatusProvider) != HubAppStatus.available) {
        return detail;
      }
      try {
        return await ref
            .read(productRouteRepositoryProvider)
            .fetchDetail(productRouteUrl(urlKey));
      } on Failure {
        // Still "not found", as before the second look.
        return null;
      }
    });

/// What HubApp adds to the product page — who sells it, other sellers'
/// offers, a bundle's options — or null: without HubApp, while its probe
/// runs, or when the read fails (the page then stays as it is today). A
/// server that turns `hm_seller` down is remembered, so the cart and orders
/// stop asking too; one that serves sellers without offers (P2) is asked
/// again without them, and from then on only without them.
final productMarketplaceProvider = FutureProvider.autoDispose
    .family<ProductMarketplace?, String>((ref, urlKey) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      if (!ref.watch(marketplaceFeaturesProvider.select((f) => f.sellers))) {
        return null;
      }
      final repository = ref.watch(productMarketplaceRepositoryProvider);
      final withOffers = !ref.read(productOffersMissingProvider);
      try {
        return await repository.fetch(urlKey, withOffers: withOffers);
      } on HubAppMissing catch (missing) {
        if (withOffers && isOffersMissing(missing)) {
          ref.read(productOffersMissingProvider.notifier).offersMissing();
          try {
            return await repository.fetch(urlKey, withOffers: false);
          } on HubAppMissing {
            ref.read(marketplaceMissingProvider.notifier).sellersMissing();
            return null;
          } on Failure {
            return null;
          }
        }
        ref.read(marketplaceMissingProvider.notifier).sellersMissing();
        return null;
      } on Failure {
        return null;
      }
    });

/// Review rating metadata for the "Write a review" star selector.
final reviewRatingsMetadataProvider =
    FutureProvider.autoDispose<List<ReviewRatingMetadata>>((ref) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return ref.watch(catalogRepositoryProvider).fetchReviewRatingsMetadata();
    });
