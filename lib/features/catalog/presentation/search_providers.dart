import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/category.dart';
import '../domain/search_facets.dart';
import 'catalog_providers.dart';
import 'search_controller.dart';

/// Top-level menu categories that hold products, in the admin's order: the
/// search landing's "Popular categories" and the type-ahead's scope list.
/// The same set Home's "Shop by category" shows, so their stand-in thumbnails
/// share one cached lookup.
final searchCategoryChoicesProvider =
    FutureProvider.autoDispose<List<Category>>((ref) async {
      final tree = await ref.watch(categoryTreeProvider.future);
      return tree.where((c) => c.productCount > 0).toList(growable: false);
    });

/// The categories one search's results fall into, best first — derived from
/// the loaded results (see [searchCategoriesFrom]), so it costs no request.
final searchResultCategoriesProvider = Provider.autoDispose
    .family<List<SearchCategory>, SearchRequest>((ref, request) {
      final state = ref.watch(searchControllerProvider(request));
      final tree =
          ref.watch(categoryTreeProvider).valueOrNull ?? const <Category>[];
      return searchCategoriesFrom(
        aggregations: state.aggregations,
        products: state.products,
        tree: tree,
        excludeUid: request.categoryUid,
      );
    });
