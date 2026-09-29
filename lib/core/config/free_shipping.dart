import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../graphql/graphql_client.dart';
import '../store/store_controller.dart';

/// Fetches the storefront's free-shipping threshold — Magento's Free Shipping
/// method "Minimum Order Amount" (`carriers/freeshipping/free_shipping_subtotal`),
/// exposed on `storeConfig` as the string field `free_shipping_subtotal`
/// (e.g. "200"). The app must NOT hardcode this value; it is store-config driven
/// so the business can change the threshold without an app release.
class FreeShippingRepository {
  FreeShippingRepository(this._client);

  final GraphQLClient _client;

  static const String _query = r'''
query FreeShippingSubtotal {
  storeConfig { free_shipping_subtotal }
}
''';

  /// The configured threshold in the store currency (AED), or null when it is
  /// unset / 0 / unavailable — callers then hide free-shipping messaging rather
  /// than promise a threshold that isn't configured.
  Future<double?> fetchThreshold() async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(_query),
          // The value is effectively static per store view — cache it.
          fetchPolicy: FetchPolicy.cacheFirst,
        ),
      );
      if (result.hasException) return null;
      final raw = (result.data?['storeConfig']
          as Map<String, dynamic>?)?['free_shipping_subtotal'];
      // Magento returns it as a String ("200"); tolerate num too.
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
      return (value != null && value > 0) ? value : null;
    } on Object {
      return null;
    }
  }
}

final freeShippingRepositoryProvider = Provider<FreeShippingRepository>(
  (ref) => FreeShippingRepository(ref.watch(graphqlClientProvider)),
);

/// The active store view's free-shipping threshold (AED), or null when none is
/// configured/available (also null while first loading). Refetches on a
/// store/language switch; the value can differ per store view.
final freeShippingThresholdProvider = FutureProvider<double?>((ref) {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(freeShippingRepositoryProvider).fetchThreshold();
});
