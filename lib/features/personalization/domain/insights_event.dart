/// The Algolia Insights event names the website sends (the vendored Algolia
/// extension of the storefront), so a shopper's profile is one profile whether
/// they browse the site or the app.
abstract final class InsightsEventNames {
  static const String viewedProduct = 'Viewed Product';
  static const String productClicked = 'Product Clicked';
  static const String addedToCart = 'Added to Cart';
  static const String addedToWishlist = 'Added to Wishlist';
  static const String placedOrder = 'Placed order';
}

/// One product line of a conversion: the Algolia `objectID` (the product's
/// id), its unit price and how many.
class InsightsLine {
  const InsightsLine({
    required this.objectId,
    required this.quantity,
    this.unitPrice,
  });

  final String objectId;
  final int quantity;

  /// Null when the price is not known: the event then carries no `objectData`.
  final double? unitPrice;
}

/// Algolia accepts at most 20 `objectIDs` in one event.
const int kInsightsMaxObjects = 20;

/// An Algolia Insights event, before it is stamped with the index, the shopper's
/// user token and the time (see [toJson]). The shapes follow the Insights API:
/// a `view`, a `click` and `conversion`s, the cart and purchase ones carrying
/// `objectData` and a `currency`.
class InsightsEvent {
  const InsightsEvent._({
    required this.type,
    required this.name,
    required this.objectIds,
    this.subtype,
    this.lines = const <InsightsLine>[],
    this.currency,
  });

  /// A product page was opened.
  InsightsEvent.viewed(String objectId)
    : this._(
        type: 'view',
        name: InsightsEventNames.viewedProduct,
        objectIds: [objectId],
      );

  /// A product was tapped in a list.
  InsightsEvent.clicked(String objectId)
    : this._(
        type: 'click',
        name: InsightsEventNames.productClicked,
        objectIds: [objectId],
      );

  /// A product went into the wishlist.
  InsightsEvent.addedToWishlist(String objectId)
    : this._(
        type: 'conversion',
        name: InsightsEventNames.addedToWishlist,
        objectIds: [objectId],
      );

  /// [lines] went into the cart. Without a price for every line it is the
  /// plain conversion (no subtype, no `objectData`).
  factory InsightsEvent.addedToCart(List<InsightsLine> lines, String currency) {
    final priced = lines.isNotEmpty && lines.every((l) => l.unitPrice != null);
    return InsightsEvent._(
      type: 'conversion',
      name: InsightsEventNames.addedToCart,
      objectIds: [for (final l in lines) l.objectId],
      subtype: priced ? 'addToCart' : null,
      lines: priced ? lines : const <InsightsLine>[],
      currency: priced ? currency : null,
    );
  }

  /// [lines] were bought: the order was placed.
  factory InsightsEvent.purchased(List<InsightsLine> lines, String currency) {
    final priced = lines.isNotEmpty && lines.every((l) => l.unitPrice != null);
    return InsightsEvent._(
      type: 'conversion',
      name: InsightsEventNames.placedOrder,
      objectIds: [for (final l in lines) l.objectId],
      subtype: priced ? 'purchase' : null,
      lines: priced ? lines : const <InsightsLine>[],
      currency: priced ? currency : null,
    );
  }

  final String type;
  final String name;
  final String? subtype;
  final List<String> objectIds;
  final List<InsightsLine> lines;
  final String? currency;

  /// The API payloads for this event: one per 20 products.
  List<Map<String, Object?>> toJson({
    required String index,
    required String userToken,
    required DateTime at,
  }) {
    final payloads = <Map<String, Object?>>[];
    for (var from = 0; from < objectIds.length; from += kInsightsMaxObjects) {
      final to = from + kInsightsMaxObjects < objectIds.length
          ? from + kInsightsMaxObjects
          : objectIds.length;
      payloads.add({
        'eventType': type,
        if (subtype != null) 'eventSubtype': subtype,
        'eventName': name,
        'index': index,
        'userToken': userToken,
        'timestamp': at.millisecondsSinceEpoch,
        'objectIDs': objectIds.sublist(from, to),
        if (lines.isNotEmpty)
          'objectData': [
            for (final line in lines.sublist(from, to))
              {'price': line.unitPrice, 'quantity': line.quantity},
          ],
        if (currency != null && lines.isNotEmpty) 'currency': currency,
      });
    }
    return payloads;
  }
}
