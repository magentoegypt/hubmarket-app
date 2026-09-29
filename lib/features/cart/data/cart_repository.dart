import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/util/media.dart';
import '../../catalog/domain/money.dart';
import '../domain/cart.dart';
import 'cart_queries.dart';

class CartRepository {
  CartRepository(this._client);

  final GraphQLClient _client;

  Future<String> createGuestCart() async {
    final data = await _run(
      CartQueries.createEmptyCart,
      const {},
      mutation: true,
    );
    final id = data['createEmptyCart'] as String?;
    if (id == null || id.isEmpty) {
      throw const Failure(
        FailureKind.server,
        detail: 'createEmptyCart was null',
      );
    }
    return id;
  }

  Future<String?> customerCartId() async {
    final data = await _run(
      CartQueries.customerCart,
      const {},
      mutation: false,
    );
    return (data['customerCart'] as Map<String, dynamic>?)?['id'] as String?;
  }

  Future<Cart> getCart(String cartId) async {
    final data = await _run(CartQueries.getCart, {
      'cartId': cartId,
    }, mutation: false);
    return _parseCart(
      data['cart'] as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    // Batch adds (e.g. wishlist "Add all") pass false so one unaddable item
    // (a configurable needing options) doesn't fail the whole batch — the
    // server still adds the valid items and returns the rest as user_errors.
    bool throwOnUserError = true,
  }) async {
    final data = await _run(CartQueries.addProducts, {
      'cartId': cartId,
      'items': items,
    }, mutation: true);
    final result = data['addProductsToCart'] as Map<String, dynamic>?;
    final errors = result?['user_errors'] as List<dynamic>?;
    if (throwOnUserError && errors != null && errors.isNotEmpty) {
      final message = (errors.first as Map)['message'] as String?;
      throw Failure(FailureKind.server, detail: message);
    }
    return _parseCart(
      result?['cart'] as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> updateItem(String cartId, String uid, int quantity) async {
    final data = await _run(CartQueries.updateItems, {
      'cartId': cartId,
      'items': [
        {'cart_item_uid': uid, 'quantity': quantity},
      ],
    }, mutation: true);
    return _parseCart(
      (data['updateCartItems'] as Map<String, dynamic>?)?['cart']
          as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> removeItem(String cartId, String uid) async {
    final data = await _run(CartQueries.removeItem, {
      'cartId': cartId,
      'uid': uid,
    }, mutation: true);
    return _parseCart(
      (data['removeItemFromCart'] as Map<String, dynamic>?)?['cart']
          as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> applyCoupon(String cartId, String code) async {
    final data = await _run(CartQueries.applyCoupon, {
      'cartId': cartId,
      'code': code,
    }, mutation: true);
    return _parseCart(
      (data['applyCouponToCart'] as Map<String, dynamic>?)?['cart']
          as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> removeCoupon(String cartId) async {
    final data = await _run(CartQueries.removeCoupon, {
      'cartId': cartId,
    }, mutation: true);
    return _parseCart(
      (data['removeCouponFromCart'] as Map<String, dynamic>?)?['cart']
          as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> mergeCarts(String source, String destination) async {
    final data = await _run(CartQueries.mergeCarts, {
      'source': source,
      'destination': destination,
    }, mutation: true);
    return _parseCart(
      data['mergeCarts'] as Map<String, dynamic>?,
      fallbackId: destination,
    );
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

  Cart _parseCart(Map<String, dynamic>? json, {required String fallbackId}) {
    if (json == null) return Cart(id: fallbackId);
    final items = (json['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_parseItem)
        .toList();
    final prices = json['prices'] as Map<String, dynamic>?;
    final discounts = prices?['discounts'] as List<dynamic>?;
    final coupons = json['applied_coupons'] as List<dynamic>?;
    return Cart(
      id: (json['id'] as String?) ?? fallbackId,
      items: items,
      totalQuantity: (json['total_quantity'] as num?)?.toInt() ?? 0,
      totals: CartTotals(
        grandTotal: _parseMoney(
          prices?['grand_total'] as Map<String, dynamic>?,
        ),
        subtotal: _parseMoney(
          prices?['subtotal_including_tax'] as Map<String, dynamic>?,
        ),
        discount: (discounts != null && discounts.isNotEmpty)
            ? _parseMoney(
                (discounts.first as Map<String, dynamic>)['amount']
                    as Map<String, dynamic>?,
              )
            : null,
        appliedCoupon: (coupons != null && coupons.isNotEmpty)
            ? (coupons.first as Map<String, dynamic>)['code'] as String?
            : null,
      ),
    );
  }

  CartItem _parseItem(Map<String, dynamic> json) {
    final product = json['product'] as Map<String, dynamic>?;
    final prices = json['prices'] as Map<String, dynamic>?;
    final priceRange = product?['price_range'] as Map<String, dynamic>?;
    final minimumPrice = priceRange?['minimum_price'] as Map<String, dynamic>?;
    final options = (json['configurable_options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((o) => '${o['option_label']}: ${o['value_label']}')
        .toList();
    return CartItem(
      uid: (json['uid'] as String?) ?? '',
      sku: (product?['sku'] as String?) ?? '',
      name: (product?['name'] as String?) ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      imageUrl: httpsMediaUrl(
        (product?['image'] as Map<String, dynamic>?)?['url'] as String?,
      ),
      unitPrice: _parseMoney(prices?['price'] as Map<String, dynamic>?),
      originalUnitPrice: _parseMoney(
        minimumPrice?['regular_price'] as Map<String, dynamic>?,
      ),
      rowTotal: _parseMoney(prices?['row_total'] as Map<String, dynamic>?),
      options: options,
    );
  }

  Money? _parseMoney(Map<String, dynamic>? json) {
    final value = json?['value'];
    if (value is! num) return null;
    return Money(
      amount: value.toDouble(),
      currency: (json!['currency'] as String?) ?? 'AED',
    );
  }
}

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepository(ref.watch(graphqlClientProvider)),
);
