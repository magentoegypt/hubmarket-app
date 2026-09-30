import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../marketplace/domain/product_offer.dart';
import 'bundle_product.dart';

/// What the HubApp backend adds to a product page (P3): who sells the
/// product, other sellers' offers on it, and a bundle's options — read by a
/// second, public query next to the product page's own, so today's page is
/// untouched without HubApp.
@immutable
class ProductMarketplace {
  const ProductMarketplace({
    this.seller,
    this.bundle,
    this.offerCount = 0,
    this.offers = const <ProductOffer>[],
  });

  /// `hm_seller`: null when the seller isn't approved.
  final HmSellerSummary? seller;

  /// For a bundle (or `new_bundle`) with options: what the package holds.
  final BundleProduct? bundle;

  /// `hm_offer_count`: how many other sellers offer this product — the
  /// website's "Sold by N other sellers". 0 without any, and on a server
  /// that doesn't list offers yet.
  final int offerCount;

  /// `hm_other_offers`: their offers, cheapest first.
  final List<ProductOffer> offers;

  static const ProductMarketplace empty = ProductMarketplace();
}
