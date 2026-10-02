import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/personalization/data/insights_tracker.dart';

/// An [InsightsTracker] that only writes down what it was told, for the tests
/// of the places that tell it (a tap, a cart add, an order).
class RecordingInsightsTracker implements InsightsTracker {
  /// Every call, in order, as `kind:detail`.
  final List<String> calls = <String>[];

  @override
  void productViewed(String sku) => calls.add('view:$sku');

  @override
  void productClicked(String sku) => calls.add('click:$sku');

  @override
  void addedToCart(String sku, {int quantity = 1, Money? unitPrice}) =>
      calls.add('cart:$sku x$quantity${unitPrice == null ? '' : ' @${unitPrice.amount}'}');

  @override
  void addedToWishlist(String sku) => calls.add('wishlist:$sku');

  @override
  void orderPlaced(List<TrackedLine> lines) =>
      calls.add('order:${lines.map((l) => '${l.sku} x${l.quantity}').join(',')}');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
