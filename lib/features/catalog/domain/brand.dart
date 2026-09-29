/// A storefront brand (manufacturer), returned by the `brands` query and shown
/// in the home "Explore Our Brands" rail. [optionId] is the manufacturer
/// attribute option used to filter products by this brand.
class Brand {
  const Brand({
    required this.brandId,
    required this.title,
    required this.urlKey,
    required this.url,
    required this.imageUrl,
    required this.optionId,
    required this.position,
  });

  final int brandId;
  final String title;
  final String urlKey;

  /// Absolute, store-prefixed brand page URL (`/uae-en/shopbrand/<url_key>.html`).
  final String url;

  /// Absolute logo image URL.
  final String imageUrl;

  /// Manufacturer attribute option id → filter products by this brand.
  final int? optionId;
  final int position;
}
