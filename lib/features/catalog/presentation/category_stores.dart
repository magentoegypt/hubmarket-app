import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../stores/data/stores_repository.dart';
import '../../stores/domain/store.dart';

/// The sellers the Categories page names for a category (Figma 08's "Top
/// stores in …" and the "N stores" of its banner): the best rated ones with a
/// listable product in the category or below it, and how many sellers there
/// are in all (`hmStores`, filtered by the numeric category id).
///
/// Only read while the Hub Market App's seller API is available
/// (`storesAvailableProvider`); a read that fails gives the same as a category
/// with no sellers, so the page just leaves the section out.
final categoryStoresProvider = FutureProvider.autoDispose
    .family<StoreListPage, int>((ref, categoryId) async {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      try {
        return await ref
            .watch(storesRepositoryProvider)
            .fetchStores(
              query: StoreListQuery(
                categoryId: categoryId,
                sort: StoreSort.topRated,
              ),
              pageSize: topStoresShown,
            );
      } on Object {
        return StoreListPage.empty;
      }
    });

/// Sellers the Categories page lists under a category (Figma 08 draws two).
const int topStoresShown = 2;
