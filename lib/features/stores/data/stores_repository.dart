import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../domain/store.dart';
import 'stores_queries.dart';

/// The seller directory and store pages (`hmStores`, `hmStore`), over the
/// public GET client. Returns domain entities; throws [HubAppMissing] when the
/// server has no seller API (the module isn't deployed there), a `Failure`
/// for anything else.
class StoresRepository {
  StoresRepository(this._client);

  final GraphQLClient _client;

  /// The backend's page size ceiling for `hmStores`; more is an error.
  static const int maxPageSize = 50;

  Future<StoreListPage> fetchStores({
    StoreListQuery query = const StoreListQuery(),
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    final data = await runHubAppQuery(
      _client,
      StoresQueries.storeList(query.sort),
      variables: <String, dynamic>{
        'pageSize': pageSize.clamp(1, maxPageSize),
        'currentPage': currentPage < 1 ? 1 : currentPage,
        ...query.toVariables(),
      },
    );
    return StoreListPage.fromJson(data['hmStores']);
  }

  /// The store page of [code]; null when no approved seller has that code.
  Future<StoreProfile?> fetchStore(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return null;
    final data = await runHubAppQuery(
      _client,
      StoresQueries.storePage,
      variables: <String, dynamic>{'code': trimmed},
    );
    return StoreProfile.fromJson(data['hmStore']);
  }
}

final storesRepositoryProvider = Provider<StoresRepository>(
  (ref) => StoresRepository(ref.watch(publicGraphqlClientProvider)),
);
