import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/graphql_failure_mapper.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/util/media.dart';
import '../../catalog/domain/money.dart';
import '../../marketplace/marketplace_features.dart';
import '../domain/bundle_cart_request.dart';
import '../domain/cart.dart';
import 'bundle_cart_mutation.dart';
import 'cart_queries.dart';

class CartRepository {
  CartRepository(
    this._client, {
    this._marketplace = const FixedMarketplaceGate(),
  });

  final GraphQLClient _client;

  /// Whether cart documents may ask for each line's seller (HubApp); asked at
  /// request time.
  final MarketplaceGate _marketplace;

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
    final data = await _cartRun(CartQueries.getCart, {
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
    final data = await _cartRun(CartQueries.addProducts, {
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

  /// Adds a bundle (or `new_bundle`) with its chosen selections through
  /// HubAppBundle's `hmAddBundleToCart` — the only way to send a configurable
  /// child's choices. Throws [HubAppMissing] when the server has no such
  /// mutation (after telling the gate), a [Failure] otherwise; the store's
  /// refusal of a selection comes back as a `server` failure with its message.
  Future<Cart> addBundle(String cartId, BundleCartRequest request) async {
    Future<Map<String, dynamic>> send({required bool withSellers}) {
      final mutation = BundleCartMutation.build(
        cartId,
        request,
        withSellers: withSellers,
      );
      return _run(
        mutation.document,
        mutation.variables,
        mutation: true,
        throwMissing: true,
      );
    }

    Map<String, dynamic> data;
    try {
      data = await send(withSellers: _marketplace.features.sellers);
    } on HubAppMissing catch (missing) {
      if (!missing.message.contains('hm_seller')) {
        _marketplace.bundlesMissing();
        rethrow;
      }
      // Bundles are there but sellers aren't: nothing ran (the document
      // failed validation), so sending it again without them is safe.
      _marketplace.sellersMissing();
      try {
        data = await send(withSellers: false);
      } on HubAppMissing {
        _marketplace.bundlesMissing();
        rethrow;
      }
    }
    final result = data['hmAddBundleToCart'] as Map<String, dynamic>?;
    final errors = result?['user_errors'] as List<dynamic>?;
    if (errors != null && errors.isNotEmpty) {
      final message = (errors.first as Map)['message'] as String?;
      throw Failure(FailureKind.server, detail: message);
    }
    return _parseCart(
      result?['cart'] as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> updateItem(String cartId, String uid, int quantity) async {
    final data = await _cartRun(CartQueries.updateItems, {
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
    final data = await _cartRun(CartQueries.removeItem, {
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
    final data = await _cartRun(CartQueries.applyCoupon, {
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
    final data = await _cartRun(CartQueries.removeCoupon, {
      'cartId': cartId,
    }, mutation: true);
    return _parseCart(
      (data['removeCouponFromCart'] as Map<String, dynamic>?)?['cart']
          as Map<String, dynamic>?,
      fallbackId: cartId,
    );
  }

  Future<Cart> mergeCarts(String source, String destination) async {
    final data = await _cartRun(CartQueries.mergeCarts, {
      'source': source,
      'destination': destination,
    }, mutation: true);
    return _parseCart(
      data['mergeCarts'] as Map<String, dynamic>?,
      fallbackId: destination,
    );
  }

  /// Runs a cart [document], asking for each line's seller while HubApp
  /// serves `hm_seller`. A server that turns the seller selection down
  /// ("Cannot query field") ran nothing — validation comes first — so the
  /// plain [document] goes out instead, and the gate stops asking.
  Future<Map<String, dynamic>> _cartRun(
    String document,
    Map<String, dynamic> variables, {
    required bool mutation,
  }) async {
    if (!_marketplace.features.sellers) {
      return _run(document, variables, mutation: mutation);
    }
    try {
      return await _run(
        CartQueries.withSellers(document),
        variables,
        mutation: mutation,
        throwMissing: true,
      );
    } on HubAppMissing {
      _marketplace.sellersMissing();
      return _run(document, variables, mutation: mutation);
    }
  }

  /// [throwMissing]: a "Cannot query field" answer throws [HubAppMissing]
  /// rather than a [Failure].
  Future<Map<String, dynamic>> _run(
    String document,
    Map<String, dynamic> variables, {
    required bool mutation,
    bool throwMissing = false,
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
        final exception = result.exception!;
        if (throwMissing && isHubAppMissing(exception)) {
          throw HubAppMissing(_firstMessage(exception));
        }
        throw mapOperationException(exception);
      }
      return result.data ?? const <String, dynamic>{};
    } on Failure {
      rethrow;
    } on HubAppMissing {
      rethrow;
    } catch (error) {
      throw Failure(FailureKind.unknown, detail: error.toString());
    }
  }

  static String _firstMessage(OperationException exception) {
    final errors = [
      ...exception.graphqlErrors,
      if (exception.linkException case final ServerException server)
        ...?server.parsedResponse?.errors,
    ];
    return errors.isEmpty ? '' : errors.first.message;
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
    final addresses = json['shipping_addresses'] as List<dynamic>?;
    final shippingAddress = (addresses != null && addresses.isNotEmpty)
        ? addresses.first as Map<String, dynamic>?
        : null;
    final shippingMethod =
        shippingAddress?['selected_shipping_method'] as Map<String, dynamic>?;
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
        shipping: _parseMoney(
          shippingMethod?['amount'] as Map<String, dynamic>?,
        ),
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
      seller: HmSellerSummary.fromJson(json['hm_seller']),
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
  (ref) => CartRepository(
    ref.watch(graphqlClientProvider),
    marketplace: ref.watch(marketplaceGateProvider),
  ),
);
