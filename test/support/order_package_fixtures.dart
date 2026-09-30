import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import 'marketplace_fakes.dart';

/// Order HM-100248 split by store, as HubAppOrders serves it (Figma 22): loly
/// store's package is on its way (a DHL number with a public page and an
/// Aramex number typed by hand, and a note from the store); MIA CO's is still
/// being prepared, with a discount. One delivery charge covered the order, so
/// neither package has a delivery line of its own.

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

/// `OrderItemInterface.id` of the three lines (items 101, 102, 103).
const String dressUid = 'MTAx';
const String sofaUid = 'MTAy';
const String chairUid = 'MTAz';

const String dhlNumber = '1234567890';
const String aramexNumber = '3345 1182';
const String dhlUrl =
    'https://www.dhl.com/global-en/home/tracking/tracking-express.html'
    '?submit=1&tracking-id=1234567890';

/// Names as each store view serves them.
({
  String loly,
  String mia,
  String dress,
  String sofa,
  String chair,
  String processing,
  String pending,
  String note,
})
packageNames(String locale) => locale == 'ar'
    ? (
        loly: 'متجر لولي',
        mia: 'ميا كو',
        dress: 'فستان صدر طباعة الأزهار رباط مشد خصر',
        sofa: 'كنبة سرير ركنه',
        chair: 'كرسي طعام بارجل ذهبية معدنية',
        processing: 'قيد التنفيذ',
        pending: 'قيد الانتظار',
        note: 'تم تغليف طلبك وتسليمه إلى DHL.',
      )
    : (
        loly: 'loly store',
        mia: 'MIA CO',
        dress: 'Floral Print Corset-Waist Tie Dress',
        sofa: 'Corner Sofa Bed',
        chair: 'Dining Chair with Gold Metal Legs',
        processing: 'Processing',
        pending: 'Pending',
        note: 'Packed and handed to DHL.',
      );

/// The order as the app holds it once parsed.
CustomerOrder packagedOrder({
  String locale = 'en',
  bool placedAsGuest = false,
  Money? lolyDelivery,
  List<OrderTracking> trackings = const [
    OrderTracking(title: 'DHL', number: dhlNumber, carrier: 'dhl'),
    OrderTracking(title: 'Aramex', number: aramexNumber, carrier: 'custom'),
  ],
}) {
  final n = packageNames(locale);
  final loly = seller('loly', n.loly);
  final mia = seller('mia', n.mia);
  return CustomerOrder(
    number: 'HM-100248',
    status: n.processing,
    date: '2026-09-28 10:42:00',
    id: 'MjQ4',
    placedAsGuest: placedAsGuest,
    total: _aed(528),
    subtotal: _aed(543),
    discount: _aed(25),
    shippingAmount: _aed(10),
    paymentMethodName: 'Cash on delivery',
    shipmentCount: 1,
    trackings: trackings,
    lines: [
      OrderLine(
        name: n.dress,
        quantity: 1,
        price: _aed(50),
        sku: 'DRESS',
        seller: loly,
        uid: dressUid,
      ),
      OrderLine(
        name: n.sofa,
        quantity: 1,
        price: _aed(425),
        sku: 'SOFA',
        seller: mia,
        uid: sofaUid,
      ),
      OrderLine(
        name: n.chair,
        quantity: 2,
        price: _aed(34),
        sku: 'CHAIR',
        seller: mia,
        uid: chairUid,
      ),
    ],
    packages: [
      OrderPackage(
        seller: loly,
        statusCode: 'processing',
        statusLabel: n.processing,
        state: 'processing',
        itemUids: const [dressUid],
        subtotal: _aed(50),
        shippingAmount: lolyDelivery,
        shippingMethod: lolyDelivery == null ? null : 'Vendor Table Rate',
        grandTotal: _aed(50 + (lolyDelivery?.amount ?? 0)),
        shipments: [
          OrderPackageShipment(
            id: 'MDAwMDAwMDMx',
            number: '000000031',
            createdAt: DateTime.utc(2026, 9, 29, 6, 10),
            tracks: [
              OrderPackageTrack(
                carrierCode: 'dhl',
                carrierTitle: 'DHL',
                number: dhlNumber,
                trackingUrl: Uri.parse(dhlUrl),
              ),
              const OrderPackageTrack(
                carrierCode: 'custom',
                carrierTitle: 'Aramex',
                number: aramexNumber,
              ),
            ],
          ),
        ],
        comments: [
          OrderPackageComment(
            message: n.note,
            createdAt: DateTime.utc(2026, 9, 29, 6, 5),
          ),
        ],
      ),
      OrderPackage(
        seller: mia,
        statusCode: 'pending',
        statusLabel: n.pending,
        state: 'new',
        itemUids: const [sofaUid, chairUid],
        subtotal: _aed(493),
        discount: _aed(25),
        grandTotal: _aed(468),
      ),
    ],
  );
}

/// `CustomerOrder` JSON with the HubApp twin's fields, as the server answers
/// it: each line's id and seller, and `hm_packages`.
Map<String, dynamic> packagedOrderJson() => {
  '__typename': 'CustomerOrder',
  'id': 'MjQ4',
  'number': 'HM-100248',
  'status': 'Processing',
  'order_date': '2026-09-28 10:42:00',
  'items': [
    _itemJson(dressUid, 'Floral Print Corset-Waist Tie Dress', 'loly'),
    _itemJson(sofaUid, 'Corner Sofa Bed', 'mia'),
    _itemJson(chairUid, 'Dining Chair with Gold Metal Legs', 'mia'),
  ],
  'shipments': [
    {
      '__typename': 'OrderShipment',
      'number': '000000031',
      'tracking': [
        {
          '__typename': 'ShipmentTracking',
          'title': 'DHL',
          'number': dhlNumber,
          'carrier': 'dhl',
        },
      ],
    },
  ],
  'hm_packages': [
    {
      '__typename': 'HmOrderPackage',
      'seller': sellerJson('loly', 'loly store'),
      'status_code': 'processing',
      'status_label': 'Processing',
      'state': 'processing',
      'item_uids': [dressUid],
      'subtotal': _moneyJson(50),
      'discount': null,
      'tax': null,
      'shipping_amount': null,
      'shipping_method': null,
      'grand_total': _moneyJson(50),
      'shipments': [
        {
          '__typename': 'HmOrderPackageShipment',
          'id': 'MDAwMDAwMDMx',
          'number': '000000031',
          'created_at': '2026-09-29T06:10:00Z',
          'tracks': [
            {
              '__typename': 'HmOrderPackageTrack',
              'carrier_code': 'dhl',
              'carrier_title': 'DHL',
              'number': dhlNumber,
              'tracking_url': dhlUrl,
            },
            {
              '__typename': 'HmOrderPackageTrack',
              'carrier_code': 'custom',
              'carrier_title': 'Aramex',
              'number': aramexNumber,
              'tracking_url': null,
            },
          ],
        },
      ],
      'comments': [
        {
          '__typename': 'HmOrderPackageComment',
          'message': 'Packed and handed to DHL.',
          'created_at': '2026-09-29T06:05:00Z',
        },
      ],
    },
    {
      '__typename': 'HmOrderPackage',
      'seller': sellerJson('mia', 'MIA CO'),
      'status_code': 'pending',
      'status_label': 'Pending',
      'state': 'new',
      'item_uids': [sofaUid, chairUid],
      'subtotal': _moneyJson(493),
      'discount': _moneyJson(25),
      'tax': null,
      'shipping_amount': null,
      'shipping_method': null,
      'grand_total': _moneyJson(468),
      'shipments': <Object>[],
      'comments': <Object>[],
    },
  ],
};

Map<String, dynamic> _itemJson(String uid, String name, String store) => {
  '__typename': 'OrderItem',
  'id': uid,
  'product_name': name,
  'product_sku': name.toUpperCase().split(' ').first,
  'quantity_ordered': 1,
  'hm_seller': sellerJson(store, store == 'loly' ? 'loly store' : 'MIA CO'),
};

Map<String, dynamic> _moneyJson(double value) => {
  '__typename': 'Money',
  'value': value,
  'currency': 'AED',
};
