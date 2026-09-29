import '../../../core/util/media.dart';
import '../domain/money.dart';
import '../domain/product.dart';

/// Shared parsers for the common `Money` and listing-`Product` GraphQL shapes,
/// reused by catalogue and wishlist repositories.
Money? moneyFromJson(Map<String, dynamic>? json) {
  final value = json?['value'];
  if (value is! num) return null;
  return Money(
    amount: value.toDouble(),
    currency: (json!['currency'] as String?) ?? 'AED',
  );
}

Product productFromJson(Map<String, dynamic> json) {
  final image = json['image'] as Map<String, dynamic>?;
  final minPrice =
      (json['price_range'] as Map<String, dynamic>?)?['minimum_price']
          as Map<String, dynamic>?;
  return Product(
    sku: (json['sku'] as String?) ?? '',
    name: (json['name'] as String?) ?? '',
    urlKey: (json['url_key'] as String?) ?? '',
    imageUrl: httpsMediaUrl(image?['url'] as String?),
    regularPrice: moneyFromJson(
      minPrice?['regular_price'] as Map<String, dynamic>?,
    ),
    finalPrice: moneyFromJson(
      minPrice?['final_price'] as Map<String, dynamic>?,
    ),
    inStock: (json['stock_status'] as String?) != 'OUT_OF_STOCK',
    badge: badgeFromJson(json),
  );
}

/// Maps the backend `is_new_arrival` / `is_bestseller` flags to a single
/// merchandising badge. Bestseller wins when a product qualifies for both.
/// Tolerates GraphQL Boolean or Magento Int (0/1). Absent fields → no badge.
ProductBadge badgeFromJson(Map<String, dynamic> json) {
  bool truthy(Object? v) => v == true || (v is num && v != 0);
  if (truthy(json['is_bestseller'])) return ProductBadge.bestseller;
  if (truthy(json['is_new_arrival'])) return ProductBadge.isNew;
  return ProductBadge.none;
}
