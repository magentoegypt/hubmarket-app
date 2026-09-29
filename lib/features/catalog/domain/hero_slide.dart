/// A home hero slide, managed in the Magento admin (MagentoEgypt_Beauty) and
/// returned by the `heroSlides` query, ordered by [position]. Image-first;
/// [videoUrl] is optional and [imageUrl] doubles as the video poster.
class HeroSlide {
  const HeroSlide({
    required this.slideId,
    required this.position,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.ctaLabel,
    required this.ctaUrl,
    required this.imageUrl,
    required this.videoUrl,
  });

  final int slideId;
  final int position;
  final String eyebrow;
  final String title;
  final String description;
  final String ctaLabel;

  /// Absolute, store-prefixed Magento URL (e.g. `/uae-en/catalog/category/view/id/5/`).
  final String ctaUrl;

  /// Absolute media URL — also the video poster.
  final String imageUrl;

  /// Absolute media URL; empty when the slide has no video.
  final String videoUrl;

  bool get hasVideo => videoUrl.isNotEmpty;
}
