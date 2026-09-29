import '../../catalog/domain/money.dart';

class OrderLine {
  const OrderLine({
    required this.name,
    required this.quantity,
    this.price,
    this.imageUrl,
    this.sku,
    this.urlKey,
  });

  final String name;
  final double quantity;
  final Money? price;

  /// Product thumbnail (order item's linked product), null when unavailable.
  final String? imageUrl;

  /// Product sku / url_key — for reorder and product navigation.
  final String? sku;
  final String? urlKey;
}

/// A shipment tracking entry (carrier + tracking number) for a shipped order.
class OrderTracking {
  const OrderTracking({
    required this.title,
    required this.number,
    required this.carrier,
  });

  final String title;
  final String number;
  final String carrier;
}

/// One entry of the Magento order status history (real status change comment).
class OrderComment {
  const OrderComment({required this.message, required this.timestamp});

  final String message;
  final String timestamp;
}

class CustomerOrder {
  const CustomerOrder({
    required this.number,
    required this.status,
    required this.date,
    this.total,
    this.subtotal,
    this.shippingAmount,
    this.discount,
    this.discountLabel,
    this.shippingMethod,
    this.carrier,
    this.shippingName,
    this.shippingAddress,
    this.shippingPhone,
    this.shippingCountryCode,
    this.paymentMethodName,
    this.billingName,
    this.billingAddress,
    this.billingPhone,
    this.billingCountryCode,
    this.lines = const <OrderLine>[],
    this.trackings = const <OrderTracking>[],
    this.comments = const <OrderComment>[],
    this.invoiceCount = 0,
    this.shipmentCount = 0,
  });

  final String number;
  final String status;
  final String date;
  final Money? total;
  final Money? subtotal;
  final Money? shippingAmount;

  /// Total discount applied to the order (sum of all Magento discounts), and
  /// the first discount's label (e.g. the sales-rule name), when present.
  final Money? discount;
  final String? discountLabel;

  final String? shippingMethod;
  final String? carrier;

  /// Recipient name + single-line delivery address (shipping address) + phone.
  /// The address line is street + emirate (city is de-duplicated when the app
  /// derived it from the emirate); the country is carried separately in
  /// [shippingCountryCode] and rendered on its own line (matching the website).
  final String? shippingName;
  final String? shippingAddress;
  final String? shippingPhone;

  /// ISO country code of the shipping address (e.g. `AE`) — resolved to a full,
  /// localized country name at display time so Country and Emirate never collapse
  /// into the same value.
  final String? shippingCountryCode;

  /// Payment method label (e.g. "Cash on Delivery", "Tabby").
  final String? paymentMethodName;

  /// Billing recipient name + single-line billing address + phone.
  final String? billingName;
  final String? billingAddress;
  final String? billingPhone;

  /// ISO country code of the billing address (see [shippingCountryCode]).
  final String? billingCountryCode;

  final List<OrderLine> lines;
  final List<OrderTracking> trackings;

  /// Real status-history entries (newest last), for the tracking timeline.
  final List<OrderComment> comments;

  /// How many invoices / shipments the backend has raised against this order.
  /// These are the events the tracking timeline advances on — an order is
  /// "confirmed" when it has been invoiced and "shipped" when a shipment
  /// exists, which is what the merchant sees in the admin. Counting shipments
  /// rather than tracking numbers matters: a shipment created without a
  /// tracking number is still a shipment.
  final int invoiceCount;
  final int shipmentCount;

  bool get hasTracking => trackings.isNotEmpty;
  bool get hasInvoice => invoiceCount > 0;
  bool get hasShipment => shipmentCount > 0;

  /// Distinct products in the order (matches the thumbnail count / "Items (N)").
  int get itemCount => lines.length;

  bool get isDelivered {
    final s = status.toLowerCase();
    return s.contains('complet') || s.contains('deliver');
  }

  bool get isCancelled {
    final s = status.toLowerCase();
    return s.contains('cancel') || s.contains('refund') || s.contains('closed');
  }

  /// Magento's `holded` state — a pause, not a stage. The timeline stops where
  /// it genuinely got to and the status card says so, rather than implying the
  /// order is still moving.
  bool get isOnHold => status.toLowerCase().contains('hold');
}

/// A page of customer orders (for append-on-scroll pagination).
class OrderPage {
  const OrderPage({
    required this.items,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
  });

  final List<CustomerOrder> items;
  final int currentPage;
  final int totalPages;
  final int totalCount;

  static const OrderPage empty = OrderPage(
    items: [],
    currentPage: 0,
    totalPages: 0,
    totalCount: 0,
  );
}
