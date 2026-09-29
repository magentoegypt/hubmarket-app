import '../../catalog/domain/money.dart';

class ShippingMethodOption {
  const ShippingMethodOption({
    required this.carrierCode,
    required this.methodCode,
    required this.title,
    this.amount,
  });

  final String carrierCode;
  final String methodCode;
  final String title;
  final Money? amount;

  String get id => '$carrierCode|$methodCode';
}

class PaymentMethodOption {
  const PaymentMethodOption({
    required this.code,
    required this.title,
    this.isOnline = false,
  });

  final String code;
  final String title;

  /// Magento's `is_deferred`: the method is an online integration (a card
  /// gateway, a wallet, PayPal, BNPL) rather than an offline method that
  /// completes on `placeOrder`. See [payableInApp].
  final bool isOnline;

  /// Cash on delivery, across the spellings Magento and the common COD
  /// extensions use.
  bool get isCashOnDelivery {
    final c = code.toLowerCase();
    return c.contains('cashondelivery') ||
        c.contains('cash_on_delivery') ||
        c == 'cod';
  }

  /// Magento's **Zero Subtotal Checkout** (`free`) — surfaced only when the cart
  /// grand total is 0 (e.g. fully covered by a coupon or 100%-off items). It
  /// completes the order as paid on `placeOrder`.
  bool get isFree => code.toLowerCase() == 'free';
}

/// The methods this build can take a payment with, in the backend's order.
///
/// [methods] come from `available_payment_methods` and stay the only source:
/// the app never adds a method. It keeps only Magento's offline methods (cash
/// on delivery, check / money order, bank transfer, Zero Subtotal `free`),
/// which complete on `placeOrder`. An online method needs its gateway's own
/// flow after the order is placed, which the app doesn't have yet — offering
/// one would leave the order unpaid. Keying this on `is_deferred` rather than
/// on method codes also keeps out whatever gateway the store enables next,
/// until the app integrates it.
List<PaymentMethodOption> payableInApp(List<PaymentMethodOption> methods) => [
  for (final m in methods)
    if (!m.isOnline) m,
];

class PlaceOrderResult {
  const PlaceOrderResult({required this.orderNumber, this.orderToken});

  final String orderNumber;

  /// Guest order token (`placeOrder.orderV2.token`, Magento 2.4.7+) — kept with
  /// the guest's order reference so "Track order" can look the order up later.
  /// Null for logged-in customers (the bearer authorizes).
  final String? orderToken;
}
