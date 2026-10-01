import 'package:flutter/foundation.dart';

/// What the review form (Figma 15b) shows about the product being reviewed, in
/// its top card: the photo, the name and the seller. It rides along as go_router's
/// `extra` from the product page and the Reviews screen, which have them in hand;
/// a link straight to the form has none, and the card is left out.
@immutable
class ReviewSubject {
  const ReviewSubject({
    required this.sku,
    required this.name,
    this.imageUrl,
    this.sellerName,
  });

  final String sku;
  final String name;
  final String? imageUrl;

  /// The store that sells it; null for Hub Market's own products.
  final String? sellerName;
}
