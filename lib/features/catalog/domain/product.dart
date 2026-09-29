import 'money.dart';

/// Optional merchandising badge shown on a product card. Derived from catalog
/// data only — never fabricated.
enum ProductBadge { none, isNew, bestseller }

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
  });

  final String sku;
  final String name;
  final String urlKey;
  final String? brand;
  final String? imageUrl;

  /// A smaller derivative for thumbnail-sized surfaces, when the catalogue has
  /// one. Today it never does: `image`, `small_image` and `thumbnail` all
  /// resolve to the same generated file, because the store's view.xml defines
  /// no per-role dimensions (verified against the live endpoint 2026-08-21).
  /// The field exists so the switch is a one-line mapper change once the
  /// backend adds the presets — see docs/decisions/performance.md.
  final String? thumbUrl;

  /// Catalogue (struck-through) price.
  final Money? regularPrice;

  /// Price actually charged (special price when on sale).
  final Money? finalPrice;

  final bool inStock;
  final ProductBadge badge;

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
