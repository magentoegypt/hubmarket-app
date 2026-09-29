import 'money.dart';
import 'product.dart';

/// What a listing already knows about a product when the user taps it — enough
/// to paint the top of the PDP in the first frame instead of a spinner.
///
/// Deliberately its own type rather than [Product]: it travels as go_router's
/// `extra`, so keeping it small and explicit makes the cast at the route total
/// and keeps a catalogue entity out of the routing contract.
///
/// It is always optional. A deep link, a push notification or a restored route
/// arrives without one, so nothing about the PDP's correctness may depend on it
/// — it only replaces an empty loading state with a real one.
class ProductPreview {
  const ProductPreview({
    required this.urlKey,
    this.imageUrl,
    this.name,
    this.brand,
    this.regularPrice,
    this.finalPrice,
    this.badge = ProductBadge.none,
  });

  factory ProductPreview.of(Product product) => ProductPreview(
    urlKey: product.urlKey,
    imageUrl: product.imageUrl,
    name: product.name,
    brand: product.brand,
    regularPrice: product.regularPrice,
    finalPrice: product.finalPrice,
    badge: product.badge,
  );

  final String urlKey;
  final String? imageUrl;
  final String? name;
  final String? brand;

  /// Listing prices — `price_range.minimum_price`, which can differ from the
  /// selected variant's PDP price. Safe for the loading state only; the loaded
  /// PDP always prices from its own document.
  final Money? regularPrice;
  final Money? finalPrice;

  final ProductBadge badge;

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;
}
