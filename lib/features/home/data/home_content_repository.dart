import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';

/// CMS blocks the Home screen reads. They are the storefront's own blocks
/// (Content › Blocks in Magento admin), per store view, so the website and the
/// app always show the same copy.
abstract final class HomeCmsBlocks {
  static const String deliveryPromise = 'hm_delivery_promise';
  static const String promos = 'hm_home_promos';
  static const String trust = 'hm_home_trust';

  /// The "Sell on Hub Market" card's block (a heading, a line and a link).
  static const String sell = 'hm_home_sell';

  static const List<String> all = <String>[
    deliveryPromise,
    promos,
    trust,
    sell,
  ];
}

const String _cmsBlocksQuery = r'''
query HomeCmsBlocks($ids: [String]) {
  cmsBlocks(identifiers: $ids) {
    items { identifier content }
  }
}
''';

/// Reads the admin-managed content of the Home screen. Returns raw values;
/// parsing into typed content lives in the domain layer.
class HomeContentRepository {
  HomeContentRepository(this._client);

  final GraphQLClient _client;

  /// Block content keyed by identifier. Blocks that are disabled or missing in
  /// the active store view are simply absent — their section then hides.
  Future<Map<String, String>> fetchCmsBlocks(List<String> identifiers) async {
    final data = await _query(_cmsBlocksQuery, <String, dynamic>{
      'ids': identifiers,
    });
    final items =
        (data['cmsBlocks'] as Map<String, dynamic>?)?['items'] as List<dynamic>?;
    return <String, String>{
      for (final item in (items ?? const []).whereType<Map<String, dynamic>>())
        if ((item['identifier'] as String?) != null)
          item['identifier'] as String: (item['content'] as String?) ?? '',
    };
  }

  Future<Map<String, dynamic>> _query(
    String document,
    Map<String, dynamic> variables,
  ) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        throw mapOperationException(result.exception!);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }
}

final homeContentRepositoryProvider = Provider<HomeContentRepository>(
  (ref) => HomeContentRepository(ref.watch(graphqlClientProvider)),
);
