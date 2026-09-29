import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../data/home_content_repository.dart';
import '../domain/home_content.dart';

/// How many category product rails Home shows, and how many products each.
const int kHomeRailCount = 6;
const int kHomeRailSize = 10;

/// The Home CMS blocks for the active store view, keyed by identifier.
final homeCmsBlocksProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) {
  // Kept alive: tiny, and the splash warms it so Home paints on arrival.
  // A store switch still refetches via the activeStoreCode watch.
  ref.keepAlive();
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref
      .watch(homeContentRepositoryProvider)
      .fetchCmsBlocks(HomeCmsBlocks.all);
});

/// The one-line delivery promise (`hm_delivery_promise`); empty hides the strip.
final homePromiseProvider = Provider.autoDispose<String>((ref) {
  final html = ref.watch(homeCmsBlocksProvider).valueOrNull?[HomeCmsBlocks.deliveryPromise];
  return html == null ? '' : HomeContentParser.plainText(html);
});

/// Promo cards (`hm_home_promos`).
final homePromosProvider = Provider.autoDispose<List<PromoTile>>((ref) {
  final html = ref.watch(homeCmsBlocksProvider).valueOrNull?[HomeCmsBlocks.promos];
  return html == null ? const <PromoTile>[] : HomeContentParser.promos(html);
});

/// Trust row (`hm_home_trust`).
final homeTrustProvider = Provider.autoDispose<List<TrustItem>>((ref) {
  final html = ref.watch(homeCmsBlocksProvider).valueOrNull?[HomeCmsBlocks.trust];
  return html == null ? const <TrustItem>[] : HomeContentParser.trust(html);
});

/// Top-level categories that hold products, in the admin's category order —
/// the Shop by category carousel and the source of the product rails.
final homeCategoriesProvider = FutureProvider.autoDispose<List<Category>>((
  ref,
) async {
  final categories = await ref.watch(categoryTreeProvider.future);
  return categories.where((c) => c.productCount > 0).toList(growable: false);
});

/// Today's Deals: products with a live special price anywhere in the
/// catalogue, deepest discount first. Special prices and their dates are set
/// per product in Catalog › Products (Advanced Pricing), as on the website.
final homeDealsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final root = await ref.watch(homeContentRepositoryProvider).fetchRootCategoryUid();
  if (root == null) return const <Product>[];
  final page = await ref
      .watch(catalogRepositoryProvider)
      .fetchProducts(categoryUid: root, pageSize: 60);
  final deals = page.items.where((p) => p.discountPercent != null).toList()
    ..sort((a, b) => (b.discountPercent ?? 0).compareTo(a.discountPercent ?? 0));
  return deals.take(12).toList(growable: false);
});

/// Products for one category rail.
final homeCategoryRailProvider = FutureProvider.autoDispose
    .family<List<Product>, String>((ref, categoryUid) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final page = await ref
          .watch(catalogRepositoryProvider)
          .fetchProducts(categoryUid: categoryUid, pageSize: kHomeRailSize);
      return page.items;
    });
