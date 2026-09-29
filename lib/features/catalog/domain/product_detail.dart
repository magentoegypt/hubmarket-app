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

/// One bar of the per-star rating distribution, e.g.
/// `stars: 5, count: 12, percent: 80`.
class RatingBar {
  const RatingBar({
    required this.stars,
    required this.count,
    required this.percent,
  });

  /// 1–5.
  final int stars;

  /// Reviews whose rating rounds to [stars].
  final int count;

  /// Share of the rated reviews, 0–100 (rounded).
  final int percent;

  /// The 5★ → 1★ distribution of [reviews], bucketed by each review's rounded
  /// star rating ([ProductReview.stars], the same stars its card shows).
  ///
  /// Magento core has no histogram field, so it is derived from the reviews
  /// the PDP loaded. Reviews without a usable rating are left out; when none
  /// is rated the result is empty — bars are never drawn for ratings that
  /// don't exist.
  static List<RatingBar> histogramOf(Iterable<ProductReview> reviews) {
    final counts = List<int>.filled(6, 0);
    var rated = 0;
    for (final review in reviews) {
      final stars = review.stars;
      if (stars < 1 || stars > 5) continue;
      counts[stars]++;
      rated++;
    }
    if (rated == 0) return const <RatingBar>[];
    return List.unmodifiable([
      for (var stars = 5; stars >= 1; stars--)
        RatingBar(
          stars: stars,
          count: counts[stars],
          percent: (counts[stars] * 100 / rated).round(),
        ),
    ]);
  }
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

  /// Merchandising badge — NEW from the core `new_from_date` / `new_to_date`
  /// window; never BESTSELLER (see [ProductBadge]).
  final ProductBadge badge;
  final List<ConfigurableOption> options;
  final List<ProductVariant> variants;

  /// 0–100 (Magento `rating_summary`).
  final int ratingSummary;
  final int reviewCount;
  /// The first page of published reviews (the PDP query loads up to 20).
  final List<ProductReview> reviews;

  /// Per-star distribution bars (5★→1★) derived from the loaded [reviews]
  /// (see [RatingBar.histogramOf]); empty when none is rated. With more than
  /// one page of reviews ([reviewCount] > [reviews].length) it describes the
  /// loaded page only.
  List<RatingBar> get ratingHistogram => RatingBar.histogramOf(reviews);

  /// "You may also like" — Magento's core `related_products` then
  /// `upsell_products`, de-duplicated by SKU (without the product itself) and
  /// capped at 8. Empty when the catalogue links nothing; the rail then hides.
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
