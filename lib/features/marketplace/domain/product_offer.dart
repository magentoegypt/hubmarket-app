import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../catalog/domain/money.dart';

/// `HmProductOffer` — another seller's offer on the product on screen: the
/// website's "Sold by N other sellers" (Vnecoms "select and sell").
///
/// An offer is a product of its own — its own SKU, price, stock and seller —
/// which product search never lists: its page is read with `route`
/// ([routeUrl]), not `products(filter: {url_key})`.
@immutable
class ProductOffer {
  const ProductOffer({
    required this.uid,
    required this.sku,
    required this.urlKey,
    required this.typeId,
    required this.seller,
    required this.price,
    this.regularPrice,
    this.inStock = true,
    this.dispatchTime,
  });

  final String uid;
  final String sku;
  final String urlKey;

  /// `simple`, `configurable`, …
  final String typeId;
  final HmSellerSummary seller;

  /// The final price for the customer group (the lowest one of a
  /// configurable offer).
  final Money price;
  final Money? regularPrice;
  final bool inStock;
  final HmDispatchTime? dispatchTime;

  /// Whether [regularPrice] is struck through next to [price].
  bool get isDiscounted =>
      regularPrice != null && regularPrice!.amount > price.amount;

  /// A simple or virtual offer goes into the cart by its SKU, as the product
  /// page adds; any other type is bought with choices made on its own page.
  bool get addsDirectly => typeId == 'simple' || typeId == 'virtual';

  /// The store-relative URL `route` reads the offer's page by.
  String get routeUrl => productRouteUrl(urlKey);
}

/// A product page's store-relative URL for `route`: [urlKey] with the
/// product URL suffix (`.html` on this store, as `productUrl` builds links).
String productRouteUrl(String urlKey) {
  final key = urlKey.trim();
  return key.toLowerCase().endsWith('.html') ? key : '$key.html';
}
