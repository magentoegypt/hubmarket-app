import 'package:hubmarket_app/features/account/domain/order.dart';

import 'order_package_fixtures.dart';

/// Where order HM-100248 (see `order_package_fixtures.dart`) is, as
/// FulfillmentTracking serves it (`CustomerOrder.hm_fulfillment`, CL036-DEV17),
/// in each store view's words: the labels are the server's, the app prints them.

const String dhlTrackingNumber = '1234567890';

/// The words the server writes (`Labels`, i18n/en_US.csv and ar_SA.csv).
String statusLabelOf(String code, String locale) {
  const en = {
    'ordered': 'Order placed',
    'preparing': 'Preparing',
    'ready_for_pickup': 'Ready for courier pickup',
    'to_hub': 'On the way to our warehouse',
    'at_hub': 'At our warehouse',
    'shipped': 'Shipped',
    'on_the_way': 'On the way to you',
    'delivered': 'Delivered',
    'completed': 'Completed',
    'delayed': 'Delivery delayed',
    'on_hold': 'On hold',
    'canceled': 'Canceled',
    'refunded': 'Refunded',
  };
  const ar = {
    'ordered': 'تم تقديم الطلب',
    'preparing': 'قيد التجهيز',
    'ready_for_pickup': 'جاهز لاستلام المندوب',
    'to_hub': 'في الطريق إلى مستودعنا',
    'at_hub': 'في مستودعنا',
    'shipped': 'تم الشحن',
    'on_the_way': 'في الطريق إليك',
    'delivered': 'تم التوصيل',
    'completed': 'مكتمل',
    'delayed': 'تأخر التوصيل',
    'on_hold': 'معلّق',
    'canceled': 'تم الإلغاء',
    'refunded': 'تم الاسترداد',
  };
  return (locale == 'ar' ? ar : en)[code]!;
}

String routeLabelOf(String route, String locale) {
  const en = {
    'direct': 'From the seller to you',
    'to_hub': 'From the seller to our warehouse',
    'from_hub': 'From our warehouse to you',
  };
  const ar = {
    'direct': 'من البائع إليك',
    'to_hub': 'من البائع إلى مستودعنا',
    'from_hub': 'من مستودعنا إليك',
  };
  return (locale == 'ar' ? ar : en)[route]!;
}

Map<String, dynamic> _step(String code, String? at, String locale) => {
  '__typename': 'HmDeliveryStep',
  'status_code': code,
  'status_label': statusLabelOf(code, locale),
  'at': at,
};

Map<String, dynamic> _seller(String code, String name, {bool market = false}) =>
    {
      '__typename': 'HmSellerSummary',
      'code': code,
      'vendor_entity_id': code.length,
      'name': name,
      'logo_url': null,
      'rating': null,
      'review_count': 0,
      'product_count': 0,
      'is_marketplace': market,
      'link': null,
    };

/// One `HmDelivery` as the server writes it; [timeline] is `(code, at)` pairs.
Map<String, dynamic> deliveryJson({
  required String id,
  required String route,
  required String status,
  required List<(String, String?)> timeline,
  required List<String> itemUids,
  String locale = 'en',
  Map<String, dynamic>? seller,
  String? handledBy,
  bool tracked = true,
  Map<String, dynamic>? courier,
  String? expectedDelivery,
  String? updatedAt,
}) => {
  '__typename': 'HmDelivery',
  'id': id,
  'route': route,
  'route_label': routeLabelOf(route, locale),
  'seller': seller,
  'handled_by': handledBy,
  'status_code': status,
  'status_label': statusLabelOf(status, locale),
  'tracked': tracked,
  'courier': courier,
  'expected_delivery': expectedDelivery,
  'updated_at': updatedAt,
  'item_uids': itemUids,
  'timeline': [for (final (code, at) in timeline) _step(code, at, locale)],
};

/// A courier company with a number, and the page that tracks it when the
/// backend can build one.
Map<String, dynamic> thirdPartyCourierJson({
  String locale = 'en',
  String name = 'DHL',
  String? number = dhlTrackingNumber,
  String? url =
      'https://www.dhl.com/global-en/home/tracking/tracking-express.html'
      '?submit=1&tracking-id=1234567890',
}) => {
  '__typename': 'HmDeliveryCourier',
  'type': 'third_party',
  'label': locale == 'ar' ? 'شركة الشحن' : 'Courier',
  'name': name,
  'tracking_number': number,
  'tracking_url': url,
};

Map<String, dynamic> ownCourierJson({
  String locale = 'en',
  bool hubMarket = false,
}) => {
  '__typename': 'HmDeliveryCourier',
  'type': 'own',
  'label': hubMarket
      ? (locale == 'ar' ? 'توصيل هب ماركت' : 'Hub Market delivery')
      : (locale == 'ar' ? 'توصيل البائع' : "Seller's own delivery"),
  'name': null,
  'tracking_number': null,
  'tracking_url': null,
};

/// An order placed before fulfillment planning: one delivery per seller.
/// loly store's dress is on its way with DHL; MIA CO's sofa and chairs are
/// still being prepared (the order's own state; nobody recorded progress yet).
/// Overall: the slowest, preparing.
Map<String, dynamic> fulfillmentJson({String locale = 'en'}) => {
  '__typename': 'HmFulfillment',
  'status_code': 'preparing',
  'status_label': statusLabelOf('preparing', locale),
  'deliveries': [
    deliveryJson(
      id: 'delivery-1',
      route: 'direct',
      status: 'on_the_way',
      locale: locale,
      seller: _seller('loly', locale == 'ar' ? 'متجر لولي' : 'loly store'),
      handledBy: 'seller',
      courier: thirdPartyCourierJson(locale: locale),
      expectedDelivery: '2026-10-15T09:00:00+00:00',
      updatedAt: '2026-09-29T06:10:00+00:00',
      itemUids: [dressUid],
      timeline: [
        ('ordered', '2026-09-28T06:42:00+00:00'),
        ('ready_for_pickup', '2026-09-29T05:30:00+00:00'),
        ('on_the_way', '2026-09-29T06:10:00+00:00'),
      ],
    ),
    deliveryJson(
      id: 'delivery-2',
      route: 'direct',
      status: 'preparing',
      locale: locale,
      tracked: false,
      seller: _seller('mia', locale == 'ar' ? 'ميا كو' : 'MIA CO'),
      updatedAt: '2026-09-28T06:42:00+00:00',
      itemUids: [sofaUid, chairUid],
      timeline: [('ordered', '2026-09-28T06:42:00+00:00')],
    ),
  ],
};

/// A planned order routed through the Hub Market warehouse: each seller's
/// leg into it, and one leg out. The legs into the warehouse decide the overall
/// status until the leg out moves: loly's parcel is at the warehouse, MIA's is
/// still on its way there, so overall: on the way to our warehouse.
Map<String, dynamic> warehouseFulfillmentJson({String locale = 'en'}) => {
  '__typename': 'HmFulfillment',
  'status_code': 'to_hub',
  'status_label': statusLabelOf('to_hub', locale),
  'deliveries': [
    deliveryJson(
      id: 'delivery-1',
      route: 'to_hub',
      status: 'at_hub',
      locale: locale,
      seller: _seller('loly', locale == 'ar' ? 'متجر لولي' : 'loly store'),
      handledBy: 'seller',
      courier: ownCourierJson(locale: locale),
      itemUids: [dressUid],
      timeline: [
        ('ordered', '2026-09-28T06:42:00+00:00'),
        ('to_hub', '2026-09-29T08:00:00+00:00'),
        ('at_hub', '2026-09-29T14:20:00+00:00'),
      ],
    ),
    deliveryJson(
      id: 'delivery-2',
      route: 'to_hub',
      status: 'to_hub',
      locale: locale,
      seller: _seller('mia', locale == 'ar' ? 'ميا كو' : 'MIA CO'),
      handledBy: 'seller',
      courier: thirdPartyCourierJson(
        locale: locale,
        name: 'Aramex',
        number: '3345 1182',
        url: null,
      ),
      itemUids: [sofaUid, chairUid],
      timeline: [
        ('ordered', '2026-09-28T06:42:00+00:00'),
        ('to_hub', '2026-09-30T09:15:00+00:00'),
      ],
    ),
    deliveryJson(
      id: 'delivery-3',
      route: 'from_hub',
      status: 'preparing',
      locale: locale,
      seller: _seller('hub', 'Hub Market', market: true),
      handledBy: 'hub_market',
      courier: ownCourierJson(locale: locale, hubMarket: true),
      expectedDelivery: '2026-10-18T09:00:00+00:00',
      itemUids: [dressUid, sofaUid, chairUid],
      timeline: [('ordered', '2026-09-28T06:42:00+00:00')],
    ),
  ],
};

/// `CustomerOrder` JSON of order HM-100248 with the HubApp twin's fields and
/// `hm_fulfillment` ([fulfillment]; none to leave it null as the server does
/// when it could not read the order's progress).
Map<String, dynamic> fulfilledOrderJson({
  Object? fulfillment = _defaultFulfillment,
  String locale = 'en',
}) => {
  ...packagedOrderJson(),
  'hm_fulfillment': identical(fulfillment, _defaultFulfillment)
      ? fulfillmentJson(locale: locale)
      : fulfillment,
};

const Object _defaultFulfillment = Object();

/// [fulfillmentJson] (or [warehouseFulfillmentJson]) as the app holds it.
OrderFulfillment fulfillmentOf({
  String locale = 'en',
  bool warehouse = false,
}) => OrderFulfillment.fromJson(
  warehouse
      ? warehouseFulfillmentJson(locale: locale)
      : fulfillmentJson(locale: locale),
)!;

/// Order HM-100248 as the app holds it, with where its parcels are; [trackings]
/// are the order's own shipment numbers (DHL's and an Aramex one by default).
CustomerOrder fulfilledOrder({
  String locale = 'en',
  bool warehouse = false,
  List<OrderTracking>? trackings,
}) {
  final fulfillment = fulfillmentOf(locale: locale, warehouse: warehouse);
  return trackings == null
      ? packagedOrder(locale: locale, fulfillment: fulfillment)
      : packagedOrder(
          locale: locale,
          fulfillment: fulfillment,
          trackings: trackings,
        );
}
