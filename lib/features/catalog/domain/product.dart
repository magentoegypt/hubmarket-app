import 'money.dart';

/// Optional merchandising badge shown on a product card. Derived from catalog
/// data only — never fabricated.
///
/// [isNew] comes from Magento's core `new_from_date` / `new_to_date` window.
/// [bestseller] stays renderable but is currently never produced: Hub Market
/// has no bestseller attribute to back it (see `badgeFromJson`).
enum ProductBadge { none, isNew, bestseller }

/// A category a product is filed under (`items.categories`). Only the search
/// query asks for these — every other listing leaves [Product.categories]
/// empty.
class ProductCategoryRef {
  const ProductCategoryRef({
    required this.uid,
    required this.name,
    this.level = 0,
    this.inMenu = true,
  });

  final String uid;
  final String name;

  /// Depth as Magento counts it: 1 is the store root, 2 a top-level category.
  final int level;

  /// The category's own `include_in_menu` flag.
  final bool inMenu;
}

/// A catalogue product as needed for listing (home / PLP / search) and the PDP
/// summary. Richer PDP data (gallery, configurable options, variants) is added
/// in the PDP slice.
class Product {
  const Product({
    required this.sku,
    required this.name,
    required this.urlKey,
    this.brand,
    this.imageUrl,
    this.thumbUrl,
    this.regularPrice,
    this.finalPrice,
    this.inStock = true,
    this.badge = ProductBadge.none,
    this.categories = const <ProductCategoryRef>[],
    this.typeId,
    this.ratingSummary,
    this.reviewCount,
    this.sellerName,
    this.sellerCode,
    this.sellerKnown = false,
  });

  final String sku;
  final String name;
  final String urlKey;
  final String? brand;
  final String? imageUrl;

  /// A smaller derivative for thumbnail-sized surfaces, when the catalogue has
  /// one. Today it never does: `image`, `small_image` and `thumbnail` all
  /// resolve to the same generated cache file, because the theme's view.xml
  /// defines no per-role dimensions (checked on Hub Market 2026-09-29).
  /// The field exists so the switch is a one-line mapper change once the
  /// backend adds the presets — see docs/zoonze-reference/decisions/performance.md.
  final String? thumbUrl;

  /// Catalogue (struck-through) price.
  final Money? regularPrice;

  /// Price actually charged (special price when on sale).
  final Money? finalPrice;

  final bool inStock;
  final ProductBadge badge;

  /// The categories the product is filed under — search results only.
  final List<ProductCategoryRef> categories;

  /// Magento's product type — `simple`, `configurable`, `bundle`, … — when
  /// the source says (Algolia records carry `type_id`, GraphQL items their
  /// `__typename`); null when unknown.
  final String? typeId;

  /// Magento's `rating_summary`: the average of the approved reviews on a
  /// 0–100 scale (4★ is 80). Null when the listing didn't ask for it.
  final double? ratingSummary;

  /// Approved reviews (`review_count`). Null when the source doesn't say:
  /// Algolia records carry the average only.
  final int? reviewCount;

  /// Who sells the product, as the card's seller line names it (Figma v3):
  /// the seller's display name in the store view's language. Null for Hub
  /// Market's own products — the website's card leaves the line empty for
  /// them — and when the listing didn't ask ([sellerKnown]).
  final String? sellerName;

  /// The seller's code (its store page), when known.
  final String? sellerCode;

  /// Whether the listing said who sells the product (`hm_seller`, or an
  /// Algolia record): its card then keeps the seller line, empty for Hub
  /// Market's own products, so the cards of a row stay level.
  final bool sellerKnown;

  /// True for a product that can't go into the cart by SKU alone: a
  /// configurable (size, colour), bundle or grouped product needs its
  /// choices made on the product page first. Hub Market's own `new_bundle`
  /// type (as Algolia records name it) is a bundle too.
  bool get requiresOptions => const {
    'configurable',
    'bundle',
    'new_bundle',
    'grouped',
  }.contains(typeId);

  /// The average in stars (4.7 for a `rating_summary` of 94), or null when
  /// there is no rating to show — no reviews, or a listing that didn't ask.
  double? get starRating {
    final summary = ratingSummary;
    if (summary == null || summary <= 0 || reviewCount == 0) return null;
    return (summary / 20).clamp(0, 5).toDouble();
  }

  /// The category a search hit names in its "in Home Furniture" line: the
  /// deepest one shown in the menu, else the deepest of any. Null without
  /// categories.
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

  /// The best URL for a small surface (cart line, order row, search row):
  /// the thumbnail derivative when one exists, otherwise the main image.
  String? get thumbnail => thumbUrl ?? imageUrl;

  /// True when there is a genuine discount to display.
  bool get isOnSale {
    final r = regularPrice;
    final f = finalPrice;
    return r != null && f != null && f.amount < r.amount;
  }

  /// Discount percentage (rounded), or null when not on sale or when the
  /// markdown rounds to 0% — a sub-0.5% difference (e.g. AED 400 → 399) must
  /// not render a "-0%" badge.
  int? get discountPercent {
    if (!isOnSale) return null;
    final r = regularPrice!.amount;
    final f = finalPrice!.amount;
    if (r <= 0) return null;
    final pct = (((r - f) / r) * 100).round();
    return pct > 0 ? pct : null;
  }
}
