import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import 'bundle_product.dart';

/// What the HubApp backend adds to a product page (P3): who sells the
/// product, and a bundle's options — read by a second, public query next to
/// the product page's own, so today's page is untouched without HubApp.
@immutable
class ProductMarketplace {
  const ProductMarketplace({this.seller, this.bundle});

  /// `hm_seller`: null when the seller isn't approved.
  final HmSellerSummary? seller;

  /// For a bundle (or `new_bundle`) with options: what the package holds.
  final BundleProduct? bundle;

  static const ProductMarketplace empty = ProductMarketplace();
}
