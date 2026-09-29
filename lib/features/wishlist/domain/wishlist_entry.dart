import '../../catalog/domain/product.dart';

/// A wishlist line: the wishlist-item id (needed for removal) + the product.
class WishlistEntry {
  const WishlistEntry({required this.id, required this.product});

  final String id;
  final Product product;
}
