import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';

/// The Algolia `objectID` of products known by SKU.
///
/// The storefront's Algolia records are keyed by the product's id, which is
/// what GraphQL's base64 `uid` carries (`MjIyNg==` is `2226`, objectID 2226 —
/// checked against the live index). The app's products travel by SKU, so an
/// event asks the catalogue once for the ids it needs and remembers them.
class ProductObjectIds {
  ProductObjectIds(this._client);

  final GraphQLClient _client;

  /// SKU (lower case) → objectID.
  final Map<String, String> _known = <String, String>{};

  /// The most SKUs one request asks about (Magento's default page size).
  static const int batch = 20;

  static const String document = r'''
query ProductObjectIds($skus: [String]) {
  products(filter: { sku: { in: $skus } }, pageSize: 20) { items { sku uid } }
}
''';

  /// The objectID of each of [skus] the catalogue knows, keyed by the SKU as
  /// given. A SKU it cannot resolve (offline, unknown) is left out: its event
  /// is simply not sent.
  Future<Map<String, String>> resolve(Iterable<String> skus) async {
    final wanted = skus.toSet();
    final missing = [
      for (final sku in wanted)
        if (!_known.containsKey(sku.toLowerCase())) sku,
    ];
    for (var from = 0; from < missing.length; from += batch) {
      final part = missing.sublist(
        from,
        from + batch < missing.length ? from + batch : missing.length,
      );
      await _fetch(part);
    }
    return {
      for (final sku in wanted)
        if (_known[sku.toLowerCase()] case final id?) sku: id,
    };
  }

  /// Remembers an id learnt for free (a search hit's `objectID`).
  void remember(String sku, String objectId) {
    if (_isId(objectId)) _known[sku.toLowerCase()] = objectId;
  }

  Future<void> _fetch(List<String> skus) async {
    try {
      final result = await _client.query(
        QueryOptions(
          document: gql(document),
          variables: {'skus': skus},
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) return;
      final products = result.data?['products'];
      final items = products is Map<String, dynamic> ? products['items'] : null;
      for (final item in items is List ? items : const []) {
        if (item is! Map<String, dynamic>) continue;
        final sku = item['sku'];
        final id = idFromUid(item['uid']);
        if (sku is String && id != null) _known[sku.toLowerCase()] = id;
      }
    } on Object {
      // Offline or refused: the event is skipped.
    }
  }

  static bool _isId(String value) => RegExp(r'^\d{1,12}$').hasMatch(value);

  /// The product id inside a GraphQL `uid`, or null for anything else.
  static String? idFromUid(Object? uid) {
    if (uid is! String || uid.isEmpty) return null;
    try {
      final id = utf8.decode(base64.decode(base64.normalize(uid)));
      return _isId(id) ? id : null;
    } on FormatException {
      return null;
    }
  }
}

final productObjectIdsProvider = Provider<ProductObjectIds>(
  (ref) => ProductObjectIds(ref.watch(graphqlClientProvider)),
);
