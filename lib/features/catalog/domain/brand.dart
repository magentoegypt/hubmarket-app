/// A storefront brand (MGS › Shop by Brand), as `hmBrands` serves it. [optionId]
/// is the `mgs_brand` attribute option used to filter products by this brand.
class Brand {
  const Brand({
    required this.brandId,
    required this.title,
    required this.urlKey,
    required this.url,
    required this.imageUrl,
    required this.optionId,
    required this.position,
    this.isFeatured = false,
  });

  final int brandId;
  final String title;
  final String urlKey;

  /// Absolute, store-prefixed brand page URL.
  final String url;

  /// Absolute logo image URL (the small image, else the large one).
  final String imageUrl;

  /// `mgs_brand` attribute option id → filter products by this brand.
  final int? optionId;
  final int position;

  /// Flagged Featured in MGS › Shop by Brand.
  final bool isFeatured;
}
