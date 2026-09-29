import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../error/failure.dart';
import '../error/graphql_failure_mapper.dart';
import '../graphql/graphql_client.dart';
import 'store_view.dart';

/// Phase 0 bootstrap operation. Hand-written (the documented exception to the
/// codegen rule) because the live schema can't be introspected yet; Phase 1
/// switches catalogue ops to `graphql_codegen`.
const String _availableStoresQuery = r'''
query AvailableStores {
  availableStores(useCurrentGroup: false) {
    store_code
    store_name
    locale
    is_default_store
    base_currency_code
    default_display_currency_code
    base_url
    secure_base_url
    base_media_url
    base_link_url
  }
}
''';

class StoreRepository {
  StoreRepository(this._client);

  final GraphQLClient _client;

  /// Returns all store views. Throws a [Failure] on error.
  Future<List<StoreView>> fetchAvailableStores() async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(_availableStoresQuery),
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      final data =
          result.data?['availableStores'] as List<dynamic>? ??
          const <dynamic>[];
      return data
          .whereType<Map<String, dynamic>>()
          .map(StoreView.fromJson)
          .toList(growable: false);
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(graphqlClientProvider)),
);

/// The same repository over the **token-less** client. `StoreController` uses it
/// to re-run `availableStores` as a guest when the authenticated call failed, so
/// it can tell "the stored token is bad" from "the edge is having a moment"
/// before deciding whether to wipe the customer's session.
final guestStoreRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(guestGraphqlClientProvider)),
);
