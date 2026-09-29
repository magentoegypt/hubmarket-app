import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';

/// `storeConfig` for the active store view — the Phase 0 health-check payload.
const String _storeConfigQuery = r'''
query StoreConfig {
  storeConfig {
    store_code
    store_name
    locale
    base_currency_code
    default_display_currency_code
    base_url
    secure_base_url
    base_media_url
  }
}
''';

class StoreConfigData {
  const StoreConfigData({
    required this.storeCode,
    required this.storeName,
    required this.locale,
    required this.currency,
    required this.baseUrl,
    required this.baseMediaUrl,
  });

  final String storeCode;
  final String storeName;
  final String locale;
  final String currency;
  final String baseUrl;
  final String baseMediaUrl;

  factory StoreConfigData.fromJson(Map<String, dynamic> json) {
    final display = (json['default_display_currency_code'] as String?) ?? '';
    final base = (json['base_currency_code'] as String?) ?? '';
    return StoreConfigData(
      storeCode: (json['store_code'] as String?) ?? '',
      storeName: (json['store_name'] as String?) ?? '',
      locale: (json['locale'] as String?) ?? '',
      currency: display.isNotEmpty ? display : base,
      baseUrl: (json['base_url'] as String?) ?? '',
      baseMediaUrl: (json['base_media_url'] as String?) ?? '',
    );
  }
}

class StoreConfigRepository {
  StoreConfigRepository(this._client);

  final GraphQLClient _client;

  Future<StoreConfigData> fetch() async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(_storeConfigQuery),
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      final data = result.data?['storeConfig'] as Map<String, dynamic>?;
      if (data == null) {
        throw const Failure(FailureKind.server, detail: 'storeConfig was null');
      }
      return StoreConfigData.fromJson(data);
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final storeConfigRepositoryProvider = Provider<StoreConfigRepository>(
  (ref) => StoreConfigRepository(ref.watch(graphqlClientProvider)),
);

/// Refetches whenever the active store code changes (language switch).
final storeConfigProvider = FutureProvider.autoDispose<StoreConfigData>((ref) {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(storeConfigRepositoryProvider).fetch();
});
