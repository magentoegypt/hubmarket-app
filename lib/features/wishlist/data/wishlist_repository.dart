import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../catalog/data/product_mapper.dart';
import '../domain/wishlist_entry.dart';
import 'wishlist_queries.dart';

class WishlistData {
  const WishlistData({
    required this.id,
    this.entries = const <WishlistEntry>[],
  });
  final String id;
  final List<WishlistEntry> entries;
}

class WishlistRepository {
  WishlistRepository(this._client);

  final GraphQLClient _client;

  /// The customer's default wishlist, or null when none is returned.
  Future<WishlistData?> fetchWishlist() async {
    final data = await _run(
      WishlistQueries.getWishlist,
      const {},
      mutation: false,
    );
    final wishlists =
        (data['customer'] as Map<String, dynamic>?)?['wishlists']
            as List<dynamic>?;
    if (wishlists == null || wishlists.isEmpty) return null;
    return _parse(wishlists.first as Map<String, dynamic>);
  }

  Future<WishlistData> addProduct(String wishlistId, String sku) async {
    final data = await _run(WishlistQueries.addToWishlist, {
      'wishlistId': wishlistId,
      'items': [
        {'sku': sku, 'quantity': 1},
      ],
    }, mutation: true);
    final result = data['addProductsToWishlist'] as Map<String, dynamic>?;
    _checkUserErrors(result?['user_errors'] as List<dynamic>?);
    return _parse(result?['wishlist'] as Map<String, dynamic>?);
  }

  Future<WishlistData> removeItem(String wishlistId, String itemId) =>
      removeItems(wishlistId, [itemId]);

  /// Removes several items in one round-trip (the mutation already takes a list).
  Future<WishlistData> removeItems(
    String wishlistId,
    List<String> itemIds,
  ) async {
    final data = await _run(WishlistQueries.removeFromWishlist, {
      'wishlistId': wishlistId,
      'itemIds': itemIds,
    }, mutation: true);
    final result = data['removeProductsFromWishlist'] as Map<String, dynamic>?;
    return _parse(result?['wishlist'] as Map<String, dynamic>?);
  }

  void _checkUserErrors(List<dynamic>? errors) {
    if (errors != null && errors.isNotEmpty) {
      final message = (errors.first as Map)['message'] as String?;
      throw Failure(FailureKind.server, detail: message);
    }
  }

  WishlistData _parse(Map<String, dynamic>? json) {
    if (json == null) return const WishlistData(id: '');
    final items =
        (json['items_v2'] as Map<String, dynamic>?)?['items'] as List<dynamic>?;
    final entries = (items ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(
          (it) => WishlistEntry(
            id: it['id']?.toString() ?? '',
            product: productFromJson(
              (it['product'] as Map<String, dynamic>?) ?? const {},
            ),
          ),
        )
        .toList();
    return WishlistData(id: json['id']?.toString() ?? '', entries: entries);
  }

  Future<Map<String, dynamic>> _run(
    String document,
    Map<String, dynamic> variables, {
    required bool mutation,
  }) async {
    try {
      final result = mutation
          ? await _client.mutate(
              MutationOptions(
                document: gql(document),
                variables: variables,
                fetchPolicy: FetchPolicy.networkOnly,
              ),
            )
          : await _client.query(
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

final wishlistRepositoryProvider = Provider<WishlistRepository>(
  (ref) => WishlistRepository(ref.watch(graphqlClientProvider)),
);
