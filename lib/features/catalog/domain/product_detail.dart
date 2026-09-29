import 'money.dart';
import 'product.dart';

/// One selectable value of a configurable option (e.g. a size or a colour
/// swatch). [swatchColor] is a hex string when Magento exposes swatch data.
class SwatchValue {
  const SwatchValue({
    required this.valueIndex,
    required this.label,
    this.uid,
    this.swatchColor,
  });

  final int valueIndex;
  final String label;

  /// Option-value uid used for `addProductsToCart` selected_options.
  final String? uid;
  final String? swatchColor;
}

/// A configurable attribute (e.g. `color`, `size`) with its selectable values.
class ConfigurableOption {
  const ConfigurableOption({
    required this.attributeCode,
    required this.label,
    required this.values,
  });

  final String attributeCode;
  final String label;
  final List<SwatchValue> values;
}

/// A concrete variant of a configurable product, keyed by `attribute_code ->
/// value_index`.
class ProductVariant {
  const ProductVariant({
    required this.sku,
    required this.attributes,
    this.price,
    this.inStock = true,
    this.imageUrl,
  });

  final String sku;
  final Map<String, int> attributes;
  final Money? price;
  final bool inStock;
  final String? imageUrl;
}

/// A single published product review.
class ProductReview {
  const ProductReview({
    required this.nickname,
    required this.summary,
    required this.text,
    required this.averageRating,
    required this.date,
  });

  final String nickname;
  final String summary;
  final String text;

  /// 0–100 (Magento `average_rating`).
  final int averageRating;
  final String date;

  int get stars => (averageRating / 20).round();
}

/// One bar of the per-star rating distribution (`rating_histogram`), e.g.
/// `stars: 5, count: 12, percent: 80`. Store-scoped, computed server-side.
class RatingBar {
  const RatingBar({
    required this.stars,
    required this.count,
    required this.percent,
  });

  final int stars;
  final int count;
  final int percent;
}

/// Review rating metadata value (e.g. "5 stars" -> value_id).
class ReviewRatingValue {
  const ReviewRatingValue({required this.valueId, required this.value});
  final String valueId;
  final int value;
}

class ReviewRatingMetadata {
  const ReviewRatingMetadata({
    required this.id,
    required this.name,
    required this.values,
  });
  final String id;
  final String name;
  final List<ReviewRatingValue> values;
}

/// One storefront-visible additional attribute (the PDP "More Information"
/// table), e.g. `manufacturer` → "Emporio Armani". [code] is the Magento
/// attribute code; [value] is the resolved label/text.
class ProductAttribute {
  const ProductAttribute({required this.code, required this.value});
  final String code;
  final String value;
}

/// Full product detail for the PDP. Reviews degrade to an empty state when the
/// store has none (no fabricated stars).
class ProductDetail {
  const ProductDetail({
    required this.sku,
    required this.name,
    required this.urlKey,
    this.brand,
    this.description,
    this.shortDescription,
    this.attributes = const <ProductAttribute>[],
    this.gallery = const <String>[],
    this.regularPrice,
    this.finalPrice,
    this.inStock = true,
    this.badge = ProductBadge.none,
    this.options = const <ConfigurableOption>[],
    this.variants = const <ProductVariant>[],
    this.ratingSummary = 0,
    this.reviewCount = 0,
    this.reviews = const <ProductReview>[],
    this.ratingHistogram = const <RatingBar>[],
    this.alsoLike = const <Product>[],
  });

  final String sku;
  final String name;
  final String urlKey;
  final String? brand;

  /// Plain-text description (HTML already stripped).
  final String? description;

  /// Plain-text short description / key features (HTML already stripped).
  final String? shortDescription;

  /// Storefront-visible additional attributes for the "More Information" tab.
  final List<ProductAttribute> attributes;
  final List<String> gallery;
  final Money? regularPrice;
  final Money? finalPrice;
  final bool inStock;

  /// Merchandising badge (NEW / BESTSELLER) from `is_new_arrival`/`is_bestseller`.
  final ProductBadge badge;
  final List<ConfigurableOption> options;
  final List<ProductVariant> variants;

  /// 0–100 (Magento `rating_summary`).
  final int ratingSummary;
  final int reviewCount;
  final List<ProductReview> reviews;

  /// Per-star distribution bars (5★→1★) from `rating_histogram`. Store-scoped,
  /// computed server-side; empty when the store has no reviews.
  final List<RatingBar> ratingHistogram;

  /// "You may also like" — Magento `also_like_products` (related links, with a
  /// same-category newest-in-stock fallback applied server-side).
  final List<Product> alsoLike;

  bool get isConfigurable => options.isNotEmpty;
  bool get hasReviews => reviewCount > 0;

  bool get isOnSale {
    final r = regularPrice;
    final f = finalPrice;
    return r != null && f != null && f.amount < r.amount;
  }

  /// Discount percentage (rounded) of the final price vs the regular price, or
  /// null when not on sale or when the markdown rounds to 0% — a sub-0.5%
  /// difference (e.g. AED 400 → 399) must not render a "-0%" badge.
  int? get discountPercent {
    if (!isOnSale) return null;
    final r = regularPrice!.amount;
    final f = finalPrice!.amount;
    if (r <= 0) return null;
    final pct = (((r - f) / r) * 100).round();
    return pct > 0 ? pct : null;
  }

  /// The variant matching a full attribute selection, or null if incomplete /
  /// unavailable.
  ProductVariant? variantFor(Map<String, int> selection) {
    if (selection.length != options.length) return null;
    for (final variant in variants) {
      final matches = selection.entries.every(
        (e) => variant.attributes[e.key] == e.value,
      );
      if (matches) return variant;
    }
    return null;
  }
}
