import '../../catalog/domain/money.dart';

/// A line item in the cart.
class CartItem {
  const CartItem({
    required this.uid,
    required this.sku,
    required this.name,
    required this.quantity,
    this.imageUrl,
    this.unitPrice,
    this.originalUnitPrice,
    this.rowTotal,
    this.options = const <String>[],
  });

  final String uid;
  final String sku;
  final String name;
  final int quantity;
  final String? imageUrl;
  final Money? unitPrice;

  /// Regular (pre-discount) unit price. Shown struck-through next to
  /// [unitPrice] when it is genuinely higher (catalog/special price).
  final Money? originalUnitPrice;
  final Money? rowTotal;

  /// Display strings for chosen configurable options, e.g. "Size: 100ml".
  final List<String> options;

  /// True when the regular price is above the price actually charged.
  bool get isDiscounted =>
      unitPrice != null &&
      originalUnitPrice != null &&
      originalUnitPrice!.amount > unitPrice!.amount + 0.0001;
}

class CartTotals {
  const CartTotals({
    this.grandTotal,
    this.subtotal,
    this.discount,
    this.appliedCoupon,
  });

  final Money? grandTotal;
  final Money? subtotal;
  final Money? discount;
  final String? appliedCoupon;
}

class Cart {
  const Cart({
    required this.id,
    this.items = const <CartItem>[],
    this.totals = const CartTotals(),
    this.totalQuantity = 0,
  });

  final String id;
  final List<CartItem> items;
  final CartTotals totals;

  /// Server-authoritative total quantity (`Cart.total_quantity`).
  final int totalQuantity;

  /// Prefer the server count; fall back to summing line items.
  int get itemCount => totalQuantity > 0
      ? totalQuantity
      : items.fold(0, (sum, item) => sum + item.quantity);
  bool get isEmpty => items.isEmpty;

  static const Cart empty = Cart(id: '');
}
