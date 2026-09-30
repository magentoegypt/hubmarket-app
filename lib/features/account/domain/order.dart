import '../../../core/hubapp/hubapp_models.dart';
import '../../catalog/domain/money.dart';
import 'order_package.dart';

export 'order_package.dart';

class OrderLine {
  const OrderLine({
    required this.name,
    required this.quantity,
    this.price,
    this.imageUrl,
    this.sku,
    this.urlKey,
    this.seller,
    this.uid,
  });

  final String name;
  final double quantity;
  final Money? price;

  /// Product thumbnail (order item's linked product), null when unavailable.
  final String? imageUrl;

  /// Product sku / url_key — for reorder and product navigation.
  final String? sku;
  final String? urlKey;

  /// Who sold the line (`hm_seller`); null without HubApp, which keeps the
  /// order's items one list.
  final HmSellerSummary? seller;

  /// `OrderItemInterface.id`, which [OrderPackage.itemUids] name; asked for
  /// only with the packages (HubAppOrders), null otherwise.
  final String? uid;
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
    this.id = '',
    this.token,
    this.availableActions = const <String>{},
    this.placedAsGuest = false,
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
    this.packages = const <OrderPackage>[],
  });

  final String number;
  final String status;
  final String date;

  /// `CustomerOrder.id` — the uid `cancelOrder` takes. Empty when unknown.
  final String id;

  /// `CustomerOrder.token`, which authorises a guest's actions on the order
  /// (`requestGuestOrderCancel`). Null when the backend didn't return one.
  final String? token;

  /// `CustomerOrder.available_actions` (`CANCEL`, `REORDER`), as computed by
  /// Magento for this order right now.
  final Set<String> availableActions;

  /// Looked up through the guest queries (`guestOrder` / `guestOrderByToken`)
  /// — Magento only returns orders placed without an account there, and a
  /// guest cancels by e-mail confirmation rather than directly.
  final bool placedAsGuest;

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

  /// Payment method label, as the store names it (e.g. "Cash On Delivery").
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

  /// The order split by store (`hm_packages`, HubAppOrders): each store's
  /// status, shipments and totals. Empty without it.
  final List<OrderPackage> packages;

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

  /// Magento offers `CANCEL` for this order — cancellation is enabled for its
  /// store, it isn't complete/closed/cancelled/on hold and nothing shipped —
  /// and the app holds what the matching mutation needs (the uid for a
  /// customer, the token for a guest).
  bool get offersCancel =>
      availableActions.contains('CANCEL') &&
      (placedAsGuest ? (token ?? '').isNotEmpty : id.isNotEmpty);
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
