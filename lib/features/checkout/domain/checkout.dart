import '../../catalog/domain/money.dart';

/// The three checkout steps (Figma 17 → 18 → 18b), in order.
enum CheckoutStep { shipping, payment, review }

class ShippingMethodOption {
  const ShippingMethodOption({
    required this.carrierCode,
    required this.methodCode,
    required this.title,
    this.detail = '',
    this.amount,
  });

  final String carrierCode;
  final String methodCode;

  /// The option's name — Magento's `carrier_title` (or `method_title` when the
  /// carrier has none).
  final String title;

  /// The option's second line — `method_title`, when it adds something to
  /// [title]; empty otherwise.
  final String detail;
  final Money? amount;

  String get id => '$carrierCode|$methodCode';

  /// [title] and [detail] on one line, e.g. "Flat Rate · Fixed".
  String get label => detail.isEmpty ? title : '$title · $detail';

  bool get isFree => amount == null || amount!.amount <= 0;
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

/// The delivery address as the Ship to and Review cards show it. Captured when
/// the address is submitted, because a saved address reaches Magento by id
/// only.
class ShipTo {
  const ShipTo({
    required this.name,
    required this.telephone,
    required this.address,
    this.label,
  });

  final String name;

  /// E.164, as submitted.
  final String telephone;

  /// One line: street, apartment, emirate.
  final String address;

  /// The saved address's `address_label` ("Home", "Office"); null for a newly
  /// typed address.
  final String? label;

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.first;
  }
}

/// The delivery address on one line, in the order the frames print it (Figma 17
/// / 18b): apartment, street, area, emirate, country — "Apt 1204, Marina Gate 2,
/// Dubai Marina, Dubai, UAE". Blank parts are left out, and so is a part that
/// only repeats an earlier one (the area the app derived from the emirate).
/// [separator] is the locale's comma: ", " or the Arabic "، ".
String shipToAddressLine({
  String apartment = '',
  String street = '',
  String area = '',
  String emirate = '',
  String country = '',
  String separator = ', ',
}) {
  final parts = <String>[];
  for (final part in [apartment, street, area, emirate, country]) {
    final text = part.trim();
    if (text.isEmpty) continue;
    if (parts.any((p) => p.toLowerCase() == text.toLowerCase())) continue;
    parts.add(text);
  }
  return parts.join(separator);
}

class PlaceOrderResult {
  const PlaceOrderResult({required this.orderNumber, this.orderToken});

  final String orderNumber;

  /// Guest order token (`placeOrder.orderV2.token`, Magento 2.4.7+) — kept with
  /// the guest's order reference so "Track order" can look the order up later.
  /// Null for logged-in customers (the bearer authorizes).
  final String? orderToken;
}
