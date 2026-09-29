import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../graphql/graphql_client.dart';
import '../store/store_controller.dart';

/// Customer-facing features the store switches on and off in Magento admin,
/// read from core `storeConfig`. Every flag defaults to off: a feature the app
/// cannot confirm is enabled stays hidden rather than failing on use.
///
/// Live values (29 Sep 2026, both store views): cancellation **off**,
/// newsletter on, contact form on.
class StoreFeatures {
  const StoreFeatures({
    this.orderCancellationEnabled = false,
    this.cancellationReasons = const <String>[],
    this.newsletterEnabled = false,
    this.contactEnabled = false,
  });

  /// Sales › Order Cancellation › Enabled (`order_cancellation_enabled`).
  final bool orderCancellationEnabled;

  /// The reasons a customer picks from when cancelling
  /// (`order_cancellation_reasons`). `cancelOrder` only accepts one of these,
  /// so cancelling is offered only when the list has at least one.
  final List<String> cancellationReasons;

  /// Customers › Newsletter › Enabled (`newsletter_enabled`).
  final bool newsletterEnabled;

  /// Contacts › Contact Us › Enabled (`contact_enabled`) — gates `contactUs`.
  final bool contactEnabled;

  /// Whether customers may cancel orders at all on this store view.
  bool get canCancelOrders =>
      orderCancellationEnabled && cancellationReasons.isNotEmpty;

  static const StoreFeatures none = StoreFeatures();

  factory StoreFeatures.fromJson(Map<String, dynamic> json) => StoreFeatures(
    orderCancellationEnabled: json['order_cancellation_enabled'] == true,
    cancellationReasons: [
      for (final r in (json['order_cancellation_reasons'] as List<dynamic>?) ??
          const <dynamic>[])
        if (r is Map<String, dynamic>)
          if (((r['description'] as String?) ?? '').trim().isNotEmpty)
            (r['description'] as String).trim(),
    ],
    newsletterEnabled: json['newsletter_enabled'] == true,
    contactEnabled: json['contact_enabled'] == true,
  );
}

class StoreFeaturesRepository {
  StoreFeaturesRepository(this._client);

  final GraphQLClient _client;

  static const String _query = r'''
query StoreFeatures {
  storeConfig {
    order_cancellation_enabled
    order_cancellation_reasons { description }
    newsletter_enabled
    contact_enabled
  }
}
''';

  /// The active store view's switches; [StoreFeatures.none] when storeConfig
  /// can't be read, so nothing is offered that might not work.
  Future<StoreFeatures> fetch() async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(_query),
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) return StoreFeatures.none;
      final config = result.data?['storeConfig'];
      return config is Map<String, dynamic>
          ? StoreFeatures.fromJson(config)
          : StoreFeatures.none;
    } on Object {
      return StoreFeatures.none;
    }
  }
}

final storeFeaturesRepositoryProvider = Provider<StoreFeaturesRepository>(
  (ref) => StoreFeaturesRepository(ref.watch(graphqlClientProvider)),
);

/// The active store view's [StoreFeatures]. Refetches on a store/language
/// switch; never errors (see [StoreFeaturesRepository.fetch]).
final storeFeaturesProvider = FutureProvider<StoreFeatures>((ref) {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(storeFeaturesRepositoryProvider).fetch();
});
