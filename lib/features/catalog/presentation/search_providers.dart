import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp_providers.dart';
import '../domain/category.dart';
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
/// list — the landing then shows the app's own.
final trendingSearchesProvider = Provider<List<String>>(
  (ref) =>
      ref.watch(hmAppConfigProvider)?.search.trendingTerms ?? const <String>[],
);
