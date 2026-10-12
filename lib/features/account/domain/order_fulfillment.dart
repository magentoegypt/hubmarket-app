import 'package:flutter/foundation.dart';

import '../../../core/hubapp/hubapp_models.dart';

/// How a delivery status reads at a glance. The website colours its "Delivery
/// progress" the same four ways (`delivery.phtml`): green for what arrived,
/// amber for what is held up, red for what ended, blue for everything on its
/// way.
enum DeliveryTone {
  /// `delivered`, `completed`.
  success,

  /// `delayed`, `on_hold`.
  warning,

  /// `canceled`, `refunded`.
  danger,

  /// Every other status, and one this build doesn't know.
  info,
}

/// The tone of a delivery status [code] (`HmDelivery.status_code`).
DeliveryTone deliveryToneOf(String code) => switch (code) {
  'delivered' || 'completed' => DeliveryTone.success,
  'delayed' || 'on_hold' => DeliveryTone.warning,
  'canceled' || 'refunded' => DeliveryTone.danger,
  _ => DeliveryTone.info,
};

/// An ISO-8601 instant the server wrote in UTC, as a UTC [DateTime]; null when
/// unreadable. A time without a zone is read as UTC, which is what the backend
/// stores (`DateTime.tryParse` alone would read it as the device's).
DateTime? _utc(Object? value) {
  final text = hmString(value);
  if (text == null) return null;
  final iso = text.contains(' ') && !text.contains('T')
      ? text.replaceFirst(' ', 'T')
      : text;
  final hasZone = RegExp(
    r'(Z|[+-]\d\d(:?\d\d)?)$',
    caseSensitive: false,
  ).hasMatch(iso);
  final parsed = DateTime.tryParse(hasZone ? iso : '${iso}Z');
  return parsed?.toUtc();
}

/// `HmDeliveryStep` — one step of a delivery's timeline.
@immutable
class DeliveryStep {
  const DeliveryStep({
    required this.statusCode,
    required this.statusLabel,
    this.at,
  });

  final String statusCode;

  /// In the store view's language, as the website words it.
  final String statusLabel;

  /// UTC; null when the server did not record when.
  final DateTime? at;

  DeliveryTone get tone => deliveryToneOf(statusCode);

  /// Null without a status code.
  static DeliveryStep? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final code = hmString(json['status_code']);
    if (code == null) return null;
    return DeliveryStep(
      statusCode: code,
      statusLabel: hmString(json['status_label']) ?? code,
      at: _utc(json['at']),
    );
  }
}

/// `HmDeliveryCourier` — who carries a delivery.
@immutable
class DeliveryCourier {
  const DeliveryCourier({
    required this.type,
    required this.label,
    this.name,
    this.trackingNumber,
    this.trackingUrl,
  });

  /// `third_party` for a courier company, `own` when the seller or Hub Market
  /// delivers with its own drivers.
  final String type;

  /// "Courier", "Seller's own delivery" or "Hub Market delivery", in the store
  /// view's language.
  final String label;

  /// The courier company as recorded, for a third party.
  final String? name;
  final String? trackingNumber;

  /// The courier's public page for [trackingNumber], when the backend can build
  /// one; null otherwise (then the number is shown to be copied). Only a web
  /// page: never another scheme.
  final Uri? trackingUrl;

  bool get isThirdParty => type == 'third_party';

  /// What the row calls the carrier: the company for a third party, else the
  /// [label] ("Seller's own delivery").
  String get title => isThirdParty && name != null ? name! : label;

  /// Null without a type or a label.
  static DeliveryCourier? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final type = hmString(json['type']);
    final label = hmString(json['label']);
    if (type == null || label == null) return null;
    final url = Uri.tryParse(hmString(json['tracking_url']) ?? '');
    return DeliveryCourier(
      type: type,
      label: label,
      name: hmString(json['name']),
      trackingNumber: hmString(json['tracking_number']),
      trackingUrl: url != null && url.isScheme('https') && url.host.isNotEmpty
          ? url
          : null,
    );
  }
}

/// `HmDelivery` — one delivery of an order: one per seller for an order placed
/// before fulfillment planning, one per leg (seller to customer, seller to the
/// Hub Market warehouse, warehouse to customer) for a planned one.
@immutable
class OrderDelivery {
  const OrderDelivery({
    required this.id,
    required this.route,
    required this.routeLabel,
    required this.statusCode,
    required this.statusLabel,
    this.tracked = false,
    this.seller,
    this.handledBy,
    this.courier,
    this.expectedDelivery,
    this.updatedAt,
    this.itemUids = const <String>[],
    this.timeline = const <DeliveryStep>[],
  });

  /// Stable within the order: `delivery-1`, `delivery-2` …
  final String id;

  /// `direct`, `to_hub` or `from_hub`.
  final String route;
  final String routeLabel;
  final String statusCode;
  final String statusLabel;

  /// True when the delivery team recorded progress for it; false when the
  /// status follows the order and its Magento shipments, as the website's
  /// order page does.
  final bool tracked;

  /// Whose items travel in it: Hub Market for a consolidated leg out of the
  /// warehouse; null when the seller is no longer approved.
  final HmSellerSummary? seller;

  /// `seller`, `hub_market`, or null while not yet decided.
  final String? handledBy;
  final DeliveryCourier? courier;

  /// UTC; set when the delivery team gave one.
  final DateTime? expectedDelivery;

  /// UTC.
  final DateTime? updatedAt;

  /// `OrderItemInterface.id` of the lines it carries; a line can appear in a
  /// leg into the warehouse and again in the leg out of it.
  final List<String> itemUids;

  /// What happened, oldest first, starting with the order being placed.
  final List<DeliveryStep> timeline;

  DeliveryTone get tone => deliveryToneOf(statusCode);

  /// The leg out of the warehouse can carry several sellers' items, so no one
  /// seller is named on it (the website does the same).
  String? get sellerName => route == 'from_hub' ? null : seller?.name;

  /// Null without an id or a status.
  static OrderDelivery? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = hmString(json['id']);
    final code = hmString(json['status_code']);
    if (id == null || code == null) return null;
    final route = hmString(json['route']) ?? 'direct';
    return OrderDelivery(
      id: id,
      route: route,
      routeLabel: hmString(json['route_label']) ?? route,
      statusCode: code,
      statusLabel: hmString(json['status_label']) ?? code,
      tracked: json['tracked'] == true,
      seller: HmSellerSummary.fromJson(json['seller']),
      handledBy: hmString(json['handled_by']),
      courier: DeliveryCourier.fromJson(json['courier']),
      expectedDelivery: _utc(json['expected_delivery']),
      updatedAt: _utc(json['updated_at']),
      itemUids: List.unmodifiable(hmStrings(json['item_uids'])),
      timeline: List.unmodifiable([
        for (final step
            in json['timeline'] is List
                ? json['timeline'] as List
                : const <Object?>[])
          if (DeliveryStep.fromJson(step) case final parsed?) parsed,
      ]),
    );
  }
}

/// `HmFulfillment` (FulfillmentTracking, CL036-DEV17): where an order's parcels
/// are — the overall status and the deliveries, worded and decided by the
/// server so that the app, the website's order page and the backend never read
/// one way each.
@immutable
class OrderFulfillment {
  const OrderFulfillment({
    required this.statusCode,
    required this.statusLabel,
    this.deliveries = const <OrderDelivery>[],
  });

  /// The overall status: `ordered`, `preparing`, `ready_for_pickup`, `to_hub`,
  /// `at_hub`, `shipped`, `on_the_way`, `delivered`, `completed`, `delayed`,
  /// `on_hold`, `canceled` or `refunded`.
  final String statusCode;

  /// In the store view's language.
  final String statusLabel;
  final List<OrderDelivery> deliveries;

  DeliveryTone get tone => deliveryToneOf(statusCode);

  /// An order with nothing to deliver (a virtual product) has none, and the
  /// website hides its section then.
  bool get hasDeliveries => deliveries.isNotEmpty;

  /// Whether the courier of one of its deliveries lists the tracking [number]
  /// already (spaces do not count: "3345 1182" is "33451182"), so a screen does
  /// not list it a second time.
  bool showsTracking(String number) {
    final key = _trackingKey(number);
    return deliveries.any((delivery) {
      final listed = delivery.courier?.trackingNumber;
      return listed != null && _trackingKey(listed) == key;
    });
  }

  static String _trackingKey(String number) =>
      number.replaceAll(RegExp(r'\s+'), '');

  /// Null without a status (the server sends null when it could not read the
  /// order's progress).
  static OrderFulfillment? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final code = hmString(json['status_code']);
    if (code == null) return null;
    return OrderFulfillment(
      statusCode: code,
      statusLabel: hmString(json['status_label']) ?? code,
      deliveries: List.unmodifiable([
        for (final delivery
            in json['deliveries'] is List
                ? json['deliveries'] as List
                : const <Object?>[])
          if (OrderDelivery.fromJson(delivery) case final parsed?) parsed,
      ]),
    );
  }
}
