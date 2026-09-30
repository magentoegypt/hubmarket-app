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
    this.productCount,
    this.sellerCount,
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

  /// The products its page lists (`HmBrand.product_count`: the brand's
  /// products the storefront shows); null when the backend didn't count them
  /// (the Home's brand strip, an older backend).
  final int? productCount;

  /// The sellers of those products, Hub Market itself one of them
  /// (`HmBrand.seller_count`) — "from 2 stores"; null when not counted.
  final int? sellerCount;
}
