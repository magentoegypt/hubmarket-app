import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp_providers.dart';
import '../../../core/store/store_controller.dart';
import '../data/best_sellers_repository.dart';
import '../domain/category.dart';
import '../domain/product.dart';
import 'catalog_providers.dart';

/// Top-level menu categories that hold products, in the admin's order: the
/// search landing's "Popular categories" and the type-ahead's scope list.
/// The same set Home's "Shop by category" shows, so their stand-in thumbnails
/// share one cached lookup.
final searchCategoryChoicesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
      final tree = await ref.watch(categoryTreeProvider.future);
      return tree.where((c) => c.productCount > 0).toList(growable: false);
    });

/// The admin's search placeholder (`hmAppConfig.search.hint`, Stores ›
/// Configuration › Hub Market App); null without the Hub Market App API or a
/// configured hint — the search fields then show their own wording.
final searchHintProvider = Provider<String?>(
  (ref) => ref.watch(hmAppConfigProvider)?.search.hint,
);

/// The admin's trending searches, in their order (`hmAppConfig.search
/// .trending_terms`); empty without the Hub Market App API or a configured
/// list — the landing then leaves its Trending section out.
final trendingSearchesProvider = Provider<List<String>>(
  (ref) =>
      ref.watch(hmAppConfigProvider)?.search.trendingTerms ?? const <String>[],
);

/// The no-results page's "Popular right now" (Figma S2): the store's best
/// sellers, from the Hub Market App (`hmBestSellers`). Empty when they can't
/// be read — the rail then isn't shown. Only watched while the Hub Market App
/// is available.
final searchPopularNowProvider = FutureProvider.autoDispose<List<Product>>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  try {
    return await ref.watch(bestSellersRepositoryProvider).fetch(pageSize: 10);
  } on Object {
    return const <Product>[];
  }
});
