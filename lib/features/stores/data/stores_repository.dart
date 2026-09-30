import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../marketplace/marketplace_features.dart';
import '../domain/store.dart';
import '../domain/store_review.dart';
import 'stores_queries.dart';

/// The seller directory and store pages (`hmStores`, `hmStore`,
/// `hmStoreReviews`, `hmStoreCategories`), over the public GET client.
/// Returns domain entities; throws [HubAppMissing] when the server has no
/// seller API (the module isn't deployed there), a `Failure` for anything
/// else.
///
/// The list and page documents carry the P3.1 fields while [MarketplaceGate]
/// allows them (`storeExtras`: the server lists the `vendors` capability); a
/// server that turns them down anyway is asked again without them.
class StoresRepository {
  StoresRepository(
    this._client, {
    this._marketplace = const FixedMarketplaceGate(),
  });

  final GraphQLClient _client;
  final MarketplaceGate _marketplace;

  /// The backend's page size ceiling for `hmStores` and `hmStoreReviews`;
  /// more is an error.
  static const int maxPageSize = 50;

  Future<StoreListPage> fetchStores({
    StoreListQuery query = const StoreListQuery(),
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final data = await _withExtras(
      (extras) => runHubAppQuery(
        _client,
        StoresQueries.storeList(query.sort, extras: extras),
        variables: <String, dynamic>{
          'pageSize': pageSize.clamp(1, maxPageSize),
          'currentPage': currentPage < 1 ? 1 : currentPage,
          ...query.toVariables(),
        },
      ),
    );
    return StoreListPage.fromJson(data['hmStores']);
  }

  /// The store page of [code]; null when no approved seller has that code.
  Future<StoreProfile?> fetchStore(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final data = await _withExtras(
      (extras) => runHubAppQuery(
        _client,
        extras ? StoresQueries.storePageWithExtras : StoresQueries.storePage,
        variables: <String, dynamic>{'code': trimmed},
      ),
    );
    return StoreProfile.fromJson(data['hmStore']);
  }

  /// A page of [code]'s Reviews tab; null when no approved seller has that
  /// code. Asked only while the server lists the `vendors` capability.
  Future<StoreReviewPage?> fetchStoreReviews(
    String code, {
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final data = await runHubAppQuery(
      _client,
      StoresQueries.storeReviews,
      variables: <String, dynamic>{
        'code': trimmed,
        'pageSize': pageSize.clamp(1, maxPageSize),
        'currentPage': currentPage < 1 ? 1 : currentPage,
      },
    );
    return StoreReviewPage.fromJson(data['hmStoreReviews']);
  }

  /// The Stores chips with their seller counts. Asked only while the server
  /// lists the `vendors` capability.
  Future<StoreCategoryChips> fetchStoreCategories() async {
    final data = await runHubAppQuery(_client, StoresQueries.storeCategories);
    return StoreCategoryChips.fromJson(data['hmStoreCategories']);
  }

  /// Runs [run] with the P3.1 fields while the gate allows them; a server
  /// that turns them down ("Cannot query field", nothing ran) is asked again
  /// without them. Without the seller API at all, the second answer throws
  /// [HubAppMissing] as before.
  Future<Map<String, dynamic>> _withExtras(
    Future<Map<String, dynamic>> Function(bool extras) run,
  ) async {
    if (!_marketplace.features.storeExtras) return run(false);
    try {
      return await run(true);
    } on HubAppMissing {
      return run(false);
    }
  }
}

final storesRepositoryProvider = Provider<StoresRepository>(
  (ref) => StoresRepository(
    ref.watch(publicGraphqlClientProvider),
    marketplace: ref.watch(marketplaceGateProvider),
  ),
);
