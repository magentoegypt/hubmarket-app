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
    this.onlyLeft,
  });

  final String sku;
  final Map<String, int> attributes;
  final Money? price;
  final bool inStock;
  final String? imageUrl;

  /// Units left, when the store reports it (Magento's "Only X left" stock
  /// threshold, `only_x_left_in_stock`); null otherwise.
  final int? onlyLeft;
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

  /// From a core `ProductReview` (`average_rating` is 0–100).
  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
    nickname: (json['nickname'] as String?) ?? '',
    summary: (json['summary'] as String?) ?? '',
    text: (json['text'] as String?) ?? '',
    averageRating: (json['average_rating'] as num?)?.round() ?? 0,
    date: (json['created_at'] as String?) ?? '',
  );

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

  /// The distribution of [reviews] **only when they are all of the product's
  /// published reviews** ([reviewCount] of them); empty otherwise.
  ///
  /// Magento core has no histogram field, so bars can only be counted from
  /// reviews the app has loaded — and a page of the newest reviews says
  /// nothing about the older ones. Bars drawn from part of the set would
  /// present a guess as the product's distribution, so they appear only once
  /// every review is in hand (all of them on the PDP when there are at most
  /// 20; on the Reviews screen once the last page has loaded).
  static List<RatingBar> exactHistogram(
    List<ProductReview> reviews,
    int reviewCount,
  ) => (reviewCount > 0 && reviews.length >= reviewCount)
      ? histogramOf(reviews)
      : const <RatingBar>[];

  /// The 5★ → 1★ distribution of [reviews], bucketed by each review's rounded
  /// star rating ([ProductReview.stars], the same stars its card shows).
  ///
  /// Magento core has no histogram field, so it is derived from the reviews
  /// the PDP loaded. Reviews without a usable rating are left out; when none
  /// is rated the result is empty — bars are never drawn for ratings that
  /// don't exist. See [exactHistogram] for when it describes the product.
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
/// table), e.g. `mgs_brand` → "Samsung". [code] is the Magento attribute code;
/// [value] is the resolved text (a multiselect's labels comma-joined).
class ProductAttribute {
  const ProductAttribute({
    required this.code,
    required this.value,
    this.isBrand = false,
  });
  final String code;
  final String value;

  /// True for the catalogue's brand attribute, so the table can label the row
  /// "Brand" without knowing the store's attribute code.
  final bool isBrand;
}

/// Full product detail for the PDP. Reviews degrade to an empty state when the
/// store has none (no fabricated stars).
class ProductDetail {
  const ProductDetail({
    required this.sku,
    required this.name,
    required this.urlKey,
    this.typeId,
    this.brand,
    this.brandOptionId,
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
    this.onlyLeft,
    this.categories = const <ProductCategoryRef>[],
  });

  final String sku;
  final String name;
  final String urlKey;

  /// Magento's product type from the item's `__typename` — `simple`,
  /// `configurable`, `bundle` (a `new_bundle` too, with HubApp) …; null when
  /// unknown.
  final String? typeId;
  final String? brand;

  /// The `mgs_brand` option id of [brand] — what brand listings filter on and
  /// `hmBrands` keys brands by; null when the brand came from another
  /// attribute or the catalogue didn't say.
  final int? brandOptionId;

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

  /// Per-star distribution bars (5★→1★) counted from [reviews] — only when
  /// they are every published review ([reviewCount] ≤ the 20 the PDP loads);
  /// empty otherwise, or when none is rated. See [RatingBar.exactHistogram].
  List<RatingBar> get ratingHistogram =>
      RatingBar.exactHistogram(reviews, reviewCount);

  /// "You may also like" — Magento's core `related_products` then
  /// `upsell_products`, de-duplicated by SKU (without the product itself) and
  /// capped at 8. Empty when the catalogue links nothing; the rail then hides.
  final List<Product> alsoLike;

  /// Units left of a product with no options, when the store reports it
  /// (`only_x_left_in_stock`); a configurable's are on its [variants].
  final int? onlyLeft;

  /// The categories the product is filed under (`categories`); where the
  /// "Looking similar → See all" link goes. Empty when the query didn't say.
  final List<ProductCategoryRef> categories;

  /// The category "See all" opens: the deepest one shown in the menu, else
  /// the deepest of any (the rule a search hit's "in Home Furniture" follows).
  /// Null without categories.
  ProductCategoryRef? get primaryCategory {
    ProductCategoryRef? best;
    for (final category in categories) {
      if (best == null ||
          (category.inMenu && !best.inMenu) ||
          (category.inMenu == best.inMenu && category.level > best.level)) {
        best = category;
      }
    }
    return best;
  }

  bool get isConfigurable => options.isNotEmpty;
  bool get isBundle => typeId == 'bundle';
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

  /// Units left of what [selection] picks: the chosen variant's, or the
  /// product's own when it has no options. Null when the store doesn't say —
  /// today it doesn't, until the "Only X left" threshold is set in the admin.
  int? onlyLeftFor(Map<String, int> selection) {
    if (!isConfigurable) return onlyLeft;
    final left = variantFor(selection)?.onlyLeft;
    return left != null && left > 0 ? left : null;
  }

  /// What the low-stock line names: the chosen value of the last option, as
  /// "size M" (the option's label, lower-cased, then the value) — the frame's
  /// "Only 3 left in size M". Null for a product without options.
  String? stockOptionLabel(Map<String, int> selection) {
    if (options.isEmpty) return null;
    final option = options.last;
    final index = selection[option.attributeCode];
    for (final value in option.values) {
      if (value.valueIndex == index) {
        return '${option.label.toLowerCase()} ${value.label}'.trim();
      }
    }
    return null;
  }
}
