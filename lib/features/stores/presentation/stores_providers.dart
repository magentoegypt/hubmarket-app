import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/search_facets.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../marketplace/marketplace_features.dart';
import '../data/store_products_repository.dart';
import '../data/stores_repository.dart';
import '../domain/store.dart';
import '../domain/store_review.dart';

/// Whether the stores screens may run: the Hub Market App API answered
/// ([HubAppStatus.available]). Unknown (still probing, or offline) and
/// unavailable both mean no.
///
/// Every way into them is gated on it — the Stores list, a store page,
/// search's Vendors tab and vendor card, and the no-results page's "Popular
/// right now" and "Browse stores". Off, they are hidden and search looks
/// exactly as before; a stale link to `/stores` or `/store/…` lands on a
/// "coming soon" page instead of an error.
final storesAvailableProvider = Provider<bool>(
  (ref) => ref.watch(hubAppStatusProvider) == HubAppStatus.available,
);

/// Whether the store screens may use the P3.1 seller fields: the Reviews tab,
/// Contact vendor and the location line, the Sales figure and Call, each
/// card's category, the chips' counts. On only while the server lists the
/// `vendors` capability ([MarketplaceFeatures.storeExtras]); off, the store
/// screens are the P3 ones.
final storeExtrasProvider = Provider<bool>(
  (ref) => ref.watch(marketplaceFeaturesProvider.select((f) => f.storeExtras)),
);

/// Figma 12's chips with their seller counts (`hmStoreCategories`). Only
/// watched while [storeExtrasProvider] is on.
final storeCategoryChipsProvider =
    FutureProvider.autoDispose<StoreCategoryChips>((ref) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return ref.watch(storesRepositoryProvider).fetchStoreCategories();
    });

/// One seller's store page (Figma 13 / 13b); null for a code that isn't an
/// approved seller. Reloads on a store-view switch — the names, texts and
/// policies are per language.
final storeProfileProvider = FutureProvider.autoDispose
    .family<StoreProfile?, String>((ref, code) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return ref.watch(storesRepositoryProvider).fetchStore(code);
    });

/// The Stores list's banner (Figma 12): the first seller flagged Show on
/// Home — within the chosen category when there is one — with its store
/// page's banner photo. Null when no seller is featured.
final featuredStoreProvider = FutureProvider.autoDispose
    .family<StoreProfile?, int?>((ref, categoryId) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final repository = ref.watch(storesRepositoryProvider);
      final page = await repository.fetchStores(
        query: StoreListQuery(featured: true, categoryId: categoryId),
        pageSize: 1,
      );
      final card = page.items.firstOrNull;
      if (card == null) return null;
      // The card alone still makes a banner (on the brand colour) when the
      // store page can't be read.
      try {
        return await repository.fetchStore(card.code) ??
            StoreProfile(card: card);
      } on Object {
        return StoreProfile(card: card);
      }
    });

/// Sellers whose name or code contains [query] — search's name matches.
final storeNameMatchesProvider = FutureProvider.autoDispose
    .family<List<HmStoreCard>, String>((ref, query) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final trimmed = query.trim();
      if (trimmed.isEmpty) return const <HmStoreCard>[];
      final page = await ref
          .watch(storesRepositoryProvider)
          .fetchStores(query: StoreListQuery(name: trimmed), pageSize: 20);
      return page.items;
    });

/// Every approved seller, A–Z: names the sellers search's seller facet
/// counts. The backend lists well under a page of 50 today; a few pages are
/// read if that grows. Kept once loaded, per store view.
final storeDirectoryProvider = FutureProvider.autoDispose<List<HmStoreCard>>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final repository = ref.watch(storesRepositoryProvider);
  const maxPages = 5;
  final cards = <HmStoreCard>[];
  for (var page = 1; page <= maxPages; page++) {
    final result = await repository.fetchStores(
      query: const StoreListQuery(sort: StoreSort.name),
      pageSize: StoresRepository.maxPageSize,
      currentPage: page,
    );
    cards.addAll(result.items);
    if (!result.hasMore) break;
  }
  ref.keepAlive();
  return List.unmodifiable(cards);
});

/// "Categories in this store" (Figma 13b): the categories the seller's
/// products are filed under, from the products query's category facet. Only
/// menu categories, and only the most specific ones — "Furniture" goes when
/// "Home Furniture" is listed.
final storeCategoriesProvider = FutureProvider.autoDispose
    .family<List<SearchCategory>, int>((ref, vendorEntityId) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final page = await ref
          .watch(storeProductsRepositoryProvider)
          .fetchProducts(vendorEntityId: vendorEntityId, pageSize: 1);
      List<Category> tree;
      try {
        tree = await ref.watch(categoryTreeProvider.future);
      } on Object {
        tree = const <Category>[];
      }
      final categories = searchCategoriesFrom(
        aggregations: page.aggregations,
        products: const [],
        tree: tree,
      );
      return mostSpecificCategories(categories, tree);
    });

/// [categories] without any that is an ancestor of another in the list, in
/// their order.
List<SearchCategory> mostSpecificCategories(
  List<SearchCategory> categories,
  List<Category> tree,
) {
  final listed = {for (final c in categories) c.uid};
  final hasListedDescendant = <String>{};
  // Walks the tree once, marking every listed category above another one.
  bool visit(Category node) {
    var below = false;
    for (final child in node.children) {
      if (visit(child)) below = true;
    }
    if (below) hasListedDescendant.add(node.uid);
    return below || listed.contains(node.uid);
  }

  for (final root in tree) {
    visit(root);
  }
  return [
    for (final c in categories)
      if (!hasListedDescendant.contains(c.uid)) c,
  ];
}
