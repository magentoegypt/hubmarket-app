import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../graphql/graphql_client.dart';
import '../store/store_controller.dart';

/// Fetches the storefront's IANA timezone (`storeConfig { timezone }`, e.g.
/// `Asia/Dubai`).
///
/// Magento stamps and returns order timestamps as *naive* wall-clock strings in
/// this zone ("2026-09-16 13:46:00"), with no offset attached. Reading one back
/// without knowing the zone means guessing, so anything that renders an order
/// time needs this value — see `orderFmtDateTime`.
class StoreTimezoneRepository {
  StoreTimezoneRepository(this._client);

  final GraphQLClient _client;

  static const String _query = r'''
query StoreTimezone {
  storeConfig { timezone }
}
''';

  /// The store's IANA zone, or an empty string when unset/unavailable —
  /// callers then fall back to the device's own zone rather than shifting a
  /// timestamp by a guessed offset.
  Future<String> fetch() async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(_query),
          // Effectively static per store view — cache it.
          fetchPolicy: FetchPolicy.cacheFirst,
        ),
      );
      if (result.hasException) return '';
      final raw = (result.data?['storeConfig']
          as Map<String, dynamic>?)?['timezone'];
      return (raw as String?)?.trim() ?? '';
    } on Object {
      return '';
    }
  }
}

final storeTimezoneRepositoryProvider = Provider<StoreTimezoneRepository>(
  (ref) => StoreTimezoneRepository(ref.watch(graphqlClientProvider)),
);

/// The active store view's IANA timezone, empty when unavailable (also while
/// first loading — order times then render as they always did). Refetches on a
/// store/language switch.
final storeTimezoneProvider = FutureProvider<String>((ref) {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(storeTimezoneRepositoryProvider).fetch();
});
