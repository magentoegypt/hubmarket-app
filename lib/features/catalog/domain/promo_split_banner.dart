/// One "promo split" editorial banner (the Skincare / Makeup pair on the home
/// screen), from the backend `promoSplitBanners` query. Image-first, with an
/// eyebrow + tagline + CTA rendered over it.
class PromoSplitBanner {
  const PromoSplitBanner({
    required this.title,
    this.eyebrow = '',
    this.ctaLabel = '',
    this.ctaUrl = '',
    this.imageUrl = '',
  });

  /// Tagline, e.g. "Bare Skin, Better".
  final String title;

  /// Small uppercase label, e.g. "SKINCARE".
  final String eyebrow;
  final String ctaLabel;
  final String ctaUrl;
  final String imageUrl;

  bool get isEmpty => title.isEmpty && imageUrl.isEmpty;
}
