import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';
import '../../catalog/domain/money.dart';

/// Where a package stands, read from its Magento state (`HmOrderPackage.state`)
/// — the label itself is always the store's own ([OrderPackage.statusLabel]).
enum OrderPackageStage {
  /// `new`, `pending_payment`.
  pending,

  /// `processing`, `payment_review`.
  processing,

  /// `complete`.
  complete,

  /// `canceled`, `closed` (refunded).
  canceled,

  /// `holded`.
  onHold,

  /// A state this build doesn't know.
  unknown;

  static OrderPackageStage parse(String? state) => switch (state) {
    'new' || 'pending_payment' => pending,
    'processing' || 'payment_review' => processing,
    'complete' => complete,
    'canceled' || 'closed' => canceled,
    'holded' => onHold,
    _ => unknown,
  };
}

/// `HmOrderPackageTrack` — one tracking number of a shipment.
@immutable
class OrderPackageTrack {
  const OrderPackageTrack({
    required this.carrierTitle,
    required this.number,
    this.carrierCode = 'custom',
    this.trackingUrl,
  });

  /// `custom` for a carrier the store typed by hand, else Magento's code.
  final String carrierCode;

  /// The carrier's name as the store saved it with the number.
  final String carrierTitle;
  final String number;

  /// The carrier's public page for [number] — only for carriers whose page
  /// can be built from the code; null otherwise (then the number is copied).
  final Uri? trackingUrl;

  static OrderPackageTrack? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final number = hmString(json['number']);
    if (number == null) return null;
    final code = hmString(json['carrier_code']) ?? 'custom';
    final url = Uri.tryParse(hmString(json['tracking_url']) ?? '');
    return OrderPackageTrack(
      carrierCode: code,
      carrierTitle: hmString(json['carrier_title']) ?? code,
      number: number,
      // Only a web page is opened, never another scheme.
      trackingUrl: url != null && url.isScheme('https') && url.host.isNotEmpty
          ? url
          : null,
    );
  }
}

/// `HmOrderPackageShipment` — a shipment of the package's lines.
@immutable
class OrderPackageShipment {
  const OrderPackageShipment({
    required this.number,
    this.id = '',
    this.createdAt,
    this.tracks = const <OrderPackageTrack>[],
  });

  /// `OrderShipment.id`.
  final String id;
  final String number;

  /// UTC.
  final DateTime? createdAt;
  final List<OrderPackageTrack> tracks;

  static OrderPackageShipment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final number = hmString(json['number']);
    if (number == null) return null;
    return OrderPackageShipment(
      id: hmString(json['id']) ?? '',
      number: number,
      createdAt: hmDateTime(json['created_at']),
      tracks: List.unmodifiable([
        for (final t in json['tracks'] is List ? json['tracks'] as List : [])
          if (OrderPackageTrack.fromJson(t) case final track?) track,
      ]),
    );
  }
}

/// `HmOrderPackageComment` — what the store told the customer about the
/// package (the website's "About Your Order").
@immutable
class OrderPackageComment {
  const OrderPackageComment({required this.message, this.createdAt});

  final String message;

  /// UTC.
  final DateTime? createdAt;

  static OrderPackageComment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final message = hmString(json['message']);
    if (message == null) return null;
    return OrderPackageComment(
      message: message,
      createdAt: hmDateTime(json['created_at']),
    );
  }
}

/// `HmOrderPackage` (HubAppOrders): one store's part of an order, as Vnecoms
/// splits it — the store, its own status, the lines it ships ([itemUids],
/// `OrderItemInterface.id`), its shipments and its totals.
@immutable
class OrderPackage {
  const OrderPackage({
    required this.statusCode,
    required this.statusLabel,
    this.state = '',
    this.seller,
    this.itemUids = const <String>[],
    this.subtotal,
    this.discount,
    this.tax,
    this.shippingAmount,
    this.shippingMethod,
    this.grandTotal,
    this.shipments = const <OrderPackageShipment>[],
    this.comments = const <OrderPackageComment>[],
  });

  /// Null when the seller is no longer approved.
  final HmSellerSummary? seller;
  final String statusCode;

  /// The status as the website names it, in the store view's language.
  final String statusLabel;

  /// Magento's order state behind the status (see [stage]).
  final String state;
  final List<String> itemUids;
  final Money? subtotal;

  /// A positive amount; null when none.
  final Money? discount;

  /// Null when none.
  final Money? tax;

  /// Delivery this store charged when the order paid delivery per store; null
  /// when one charge covered the whole order (the order's shipping total).
  final Money? shippingAmount;

  /// This store's delivery method, when delivery was chosen per store.
  final String? shippingMethod;
  final Money? grandTotal;

  /// Oldest first.
  final List<OrderPackageShipment> shipments;

  /// Oldest first.
  final List<OrderPackageComment> comments;

  OrderPackageStage get stage => OrderPackageStage.parse(state);

  bool get hasShipments => shipments.isNotEmpty;

  /// Every tracking number of every shipment.
  Iterable<OrderPackageTrack> get tracks =>
      shipments.expand((shipment) => shipment.tracks);

  /// Null without a JSON object.
  static OrderPackage? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final code = hmString(json['status_code']) ?? '';
    return OrderPackage(
      seller: HmSellerSummary.fromJson(json['seller']),
      statusCode: code,
      statusLabel: hmString(json['status_label']) ?? code,
      state: hmString(json['state']) ?? '',
      itemUids: List.unmodifiable(hmStrings(json['item_uids'])),
      subtotal: _money(json['subtotal']),
      discount: _money(json['discount']),
      tax: _money(json['tax']),
      shippingAmount: _money(json['shipping_amount']),
      shippingMethod: hmString(json['shipping_method']),
      grandTotal: _money(json['grand_total']),
      shipments: List.unmodifiable([
        for (final s
            in json['shipments'] is List ? json['shipments'] as List : [])
          if (OrderPackageShipment.fromJson(s) case final shipment?) shipment,
      ]),
      comments: List.unmodifiable([
        for (final c
            in json['comments'] is List ? json['comments'] as List : [])
          if (OrderPackageComment.fromJson(c) case final comment?) comment,
      ]),
    );
  }

  /// The packages of `CustomerOrder.hm_packages`; empty when the server sent
  /// none (HubAppOrders not deployed, or an order it couldn't split).
  static List<OrderPackage> listFromJson(Object? json) => List.unmodifiable([
    for (final p in json is List ? json : const <Object?>[])
      if (fromJson(p) case final package?) package,
  ]);

  static Money? _money(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final value = hmDouble(json['value']);
    if (value == null) return null;
    return Money(amount: value, currency: hmString(json['currency']) ?? 'AED');
  }
}
