import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/order_packages.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/returns/data/return_photo_picker.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/wishlist/domain/wishlist_entry.dart';

import '../../test/support/fakes.dart';
import '../../test/support/marketplace_fakes.dart';
import '../../test/support/returns_fakes.dart';

/// Fixtures of the orders / returns / addresses / wishlist scenes
/// (scenes_orders.dart), copied from the widget tests that render the frames so
/// that the phone shows the very same data:
///
///  * E22 Order detail   test/features/account/audit_order_detail_test.dart and
///    test/features/marketplace/marketplace_render_test.dart (`p3_22_order`)
///  * E23 / 23b / 23c    test/features/returns/audit_returns_test.dart
///  * E24 / 24b          test/features/account/audit_addresses_test.dart
///  * E25 Wishlist       test/features/wishlist/audit_wishlist_test.dart
///  * E26 Track order    test/features/account/audit_guest_track_test.dart
///    (the per-store view: test/support/order_package_fixtures.dart)

Money aedMoney(double amount) => Money(amount: amount, currency: 'AED');

// ---------------------------------------------------------------- helpers ---

/// Scrolls the screen's main vertical scrollable back to its start, so a scene
/// whose `act` had to scroll to reach a button is still captured from the top
/// (the `scrolls` captures then go down from there).
Future<void> scrollToTop(WidgetTester tester) async {
  ScrollPosition? best;
  for (final element in find.byType(Scrollable).evaluate()) {
    if (element is! StatefulElement) continue;
    final state = element.state;
    if (state is! ScrollableState) continue;
    final axis = state.axisDirection;
    if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
    final position = state.position;
    if (!position.hasContentDimensions) continue;
    if (best == null || position.maxScrollExtent > best.maxScrollExtent) {
      best = position;
    }
  }
  best?.jumpTo(best.minScrollExtent);
  await tester.pump(const Duration(milliseconds: 200));
}

/// Scrolls [finder] into view and taps it, then lets the tap's animation (a
/// sheet opening, a chip filling) play. The widget tests drew the whole screen
/// at once, so they never had to scroll to a button; a phone is shorter.
///
/// A tap that would miss (the widget is off screen or under the pinned bar) is
/// an error of the scene, not a silent no-op: `tester.tap` only warns, and the
/// capture would then show a state the frame does not.
Future<void> tapVisible(
  WidgetTester tester,
  Finder finder, {
  int settleMs = 500,
}) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 100));
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: 'cannot tap ${finder.describeMatch(Plurality.one)}: it is off '
        'screen or covered',
  );
  await tester.tap(finder);
  var left = settleMs;
  while (left > 0) {
    final step = left < 100 ? left : 100;
    await tester.pump(Duration(milliseconds: step));
    left -= step;
  }
}

/// Drops the focus a typed field keeps: its ring and its blinking caret are
/// not in the frames, and would make two captures of one scene differ.
Future<void> unfocus(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 200));
}

// ----------------------------------------------------------- E22 order ---

/// The order of Figma 22: loly store's dress is on its way (shipped by
/// Aramex), MIA CO is still preparing the sofa and the chair.
CustomerOrder detailOrder(String locale, {bool cancel = true}) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  final lines = [
    OrderLine(
      name: ar
          ? 'فستان صدر طباعة الأزهار رباط مشدّ الخصر'
          : 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      price: aedMoney(50),
      sku: 'dress',
      seller: loly,
      uid: 'a',
      options: [ar ? 'مقاس: M' : 'Size: M'],
    ),
    OrderLine(
      name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
      quantity: 1,
      price: aedMoney(425),
      sku: 'sofa',
      seller: mia,
      uid: 'b',
      options: [ar ? 'اللون: تركوازي' : 'Colour: Teal'],
    ),
    OrderLine(
      name: ar
          ? 'كرسي طعام بارجل ذهبية معدنية'
          : 'Dining Chair with Gold Metal Legs',
      quantity: 2,
      price: aedMoney(34),
      sku: 'chair',
      seller: mia,
      uid: 'c',
      options: [ar ? 'اللون: أزرق فاتح' : 'Colour: Sky blue'],
    ),
  ];
  return CustomerOrder(
    number: 'HM-100248',
    status: ar ? 'قيد التنفيذ' : 'Processing',
    date: '2026-09-28 10:42:00',
    id: 'MjQ4',
    availableActions: cancel ? const {'CANCEL'} : const {},
    invoiceCount: 1,
    shipmentCount: 1,
    subtotal: aedMoney(543),
    shippingAmount: aedMoney(10),
    total: aedMoney(553),
    paymentMethodName: 'Visa •••• 4242',
    shippingName: ar ? 'سارة أحمد' : 'Sara Ahmed',
    shippingAddress: ar
        ? 'شقة 1204، مارينا غيت 2، دبي مارينا، دبي'
        : 'Apt 1204, Marina Gate 2, Dubai Marina, Dubai',
    lines: lines,
    packages: [
      OrderPackage(
        seller: loly,
        statusCode: 'processing',
        statusLabel: ar ? 'في الطريق إليك' : 'Out for delivery',
        state: 'processing',
        itemUids: const ['a'],
        shipments: [
          OrderPackageShipment(
            id: 's1',
            number: '000000031',
            createdAt: DateTime(2026, 9, 29, 9, 10),
            tracks: [
              OrderPackageTrack(
                carrierCode: 'aramex',
                carrierTitle: 'Aramex',
                number: '3345 1182',
                trackingUrl: Uri.parse('https://www.aramex.com/track/3345-1182'),
              ),
            ],
          ),
        ],
      ),
      OrderPackage(
        seller: mia,
        statusCode: 'new',
        statusLabel: ar ? 'قيد التجهيز' : 'Processing',
        state: 'new',
        itemUids: const ['b', 'c'],
      ),
    ],
  );
}

/// Both stores' phones ("Contact store" is drawn only for a store that has
/// one) and Magento's stamps read as the device's own, whatever zone the
/// device is in (the order's "Placed 28 Sep 2026, 10:42" stays what the frame
/// shows).
List<Override> detailOverrides() => [
  orderContactPhoneProvider(
    'loly',
  ).overrideWithValue(Uri.parse('tel:+971501234567')),
  orderContactPhoneProvider(
    'mia',
  ).overrideWithValue(Uri.parse('tel:+971507654321')),
  storeTimezoneProvider.overrideWith((ref) async => ''),
];

/// The same order as an order the server did not split by store: the lines
/// carry their seller, there are no packages (test/features/marketplace/
/// marketplace_render_test.dart, `p3_22_order`; Hub Market Build 1 shows the
/// lines grouped by store).
CustomerOrder byStoreOrder(String locale) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  return CustomerOrder(
    number: 'HM-100248',
    status: ar ? 'قيد التنفيذ' : 'Processing',
    date: '2026-09-28 10:42:00',
    id: 'MjQ4',
    total: aedMoney(553),
    subtotal: aedMoney(543),
    shippingAmount: aedMoney(10),
    // The test keeps the English title in both languages; the Arabic store
    // view serves its own.
    paymentMethodName: ar ? 'الدفع عند الاستلام' : 'Cash on delivery',
    lines: [
      OrderLine(
        name: ar
            ? 'فستان صدر طباعة الأزهار رباط مشد خصر'
            : 'Floral Print Corset-Waist Tie Dress',
        quantity: 1,
        price: aedMoney(50),
        sku: 'DRESS',
        seller: loly,
      ),
      OrderLine(
        name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
        quantity: 1,
        price: aedMoney(425),
        sku: 'SOFA',
        seller: mia,
      ),
      OrderLine(
        name: ar
            ? 'كرسي طعام بارجل ذهبية معدنية'
            : 'Dining Chair with Gold Metal Legs',
        quantity: 2,
        price: aedMoney(34),
        sku: 'CHAIR',
        seller: mia,
      ),
    ],
  );
}

// ---------------------------------------------------------- E23 returns ---

HmSellerSummary lolyReturnStore(bool ar) => HmSellerSummary(
  name: ar ? 'متجر لولي' : 'loly store',
  code: 'loly',
  vendorEntityId: 12,
);

/// Figma 23's order: one T-shirt from loly store, AED 43.
ReturnableOrder returnableOrder(bool ar) => ReturnableOrder(
  number: 'HM-100150',
  createdAt: '2026-09-22T08:30:00Z',
  statusLabel: ar ? 'تم التوصيل' : 'Delivered',
  items: [
    ReturnableItem(
      orderItemId: 501,
      sku: 'TS-S-GRN',
      name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
      options: [
        ReturnOption(label: ar ? 'المقاس' : 'Size', value: 'S'),
        ReturnOption(
          label: ar ? 'اللون' : 'Color',
          value: ar ? 'أخضر' : 'Green',
        ),
      ],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: lolyReturnStore(ar),
      unitPrice: aedMoney(43),
      rowTotal: aedMoney(43),
      maxRefund: aedMoney(43),
    ),
  ],
);

ReturnConfig returnConfig(bool ar) => ReturnConfig(
  reasonsEnabled: true,
  otherReasonAllowed: true,
  partialQuantityAllowed: true,
  reasons: [
    ReturnReason(
      id: 1,
      label: ar ? 'المقاس غير مناسب – صغير جدًا' : 'Doesn’t fit — too small',
    ),
    ReturnReason(id: 2, label: ar ? 'وصل تالفًا' : 'Arrived damaged'),
  ],
  attachmentExtensions: kPhotoReturnConfig.attachmentExtensions,
  attachmentMaxBytes: kPhotoReturnConfig.attachmentMaxBytes,
  attachmentMaxFiles: kPhotoReturnConfig.attachmentMaxFiles,
);

/// The three returns of Figma 23b: awaiting the store, refunded, rejected.
List<ReturnSummary> returnSummaries(bool ar) => [
  sampleReturnSummary(
    statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
    seller: lolyReturnStore(ar),
    firstItem: ReturnSummaryItem(
      name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
    ),
  ),
  sampleReturnSummary(
    id: 27,
    number: 'R-000027',
    state: ReturnState.closed,
    statusLabel: ar ? 'تم الاسترداد' : 'Refunded',
    seller: const HmSellerSummary(name: 'Test 1', code: 'test1'),
    createdAt: '2026-09-09T09:00:00Z',
    refundAmount: aedMoney(29),
    firstItem: ReturnSummaryItem(name: ar ? 'حقيبة سفر' : 'Joust Duffle Bag'),
  ),
  sampleReturnSummary(
    id: 19,
    number: 'R-000019',
    state: ReturnState.closed,
    statusCode: 'rejected',
    statusLabel: ar ? 'مرفوض' : 'Rejected',
    type: ReturnType.replace,
    seller: lolyReturnStore(ar),
    createdAt: '2026-09-02T09:00:00Z',
    firstItem: ReturnSummaryItem(name: ar ? 'قميص بولو' : 'Polo Shirt'),
  ),
];

/// Figma 23c: the customer's message and loly store's answer.
ReturnDetail returnDetail(bool ar) => sampleReturnDetail(
  arabic: ar,
  statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
  photo: false,
  canCancel: false,
  messages: [
    ReturnMessage(
      id: 1,
      author: ReturnActor.customer,
      authorName: ar ? 'سارة أحمد' : 'Sara Ahmed',
      bodyText: ar
          ? 'المقاس S صغير جدًا، أرجو ترتيب الاستلام. البطاقات ما زالت عليه.'
          : 'Size S is too small, please arrange a pickup. Tags are still on.',
      createdAt: '2026-09-24T14:02:00Z',
    ),
    ReturnMessage(
      id: 2,
      author: ReturnActor.seller,
      authorName: ar ? 'متجر لولي' : 'loly store',
      bodyText: ar
          ? 'أهلًا سارة، نعتذر عن المقاس! سيستلمه المندوب الثلاثاء 30 سبتمبر بين 10:00 و14:00.'
          : 'Hi Sara, sorry about the fit! A courier will collect it on Tue 30 Sep between 10:00 and 14:00.',
      createdAt: '2026-09-25T05:15:00Z',
    ),
  ],
);

FakeReturnsRepository returnsRepo(bool ar) => FakeReturnsRepository(
  config: returnConfig(ar),
  orders: [returnableOrder(ar)],
  summaries: returnSummaries(ar),
  details: {31: returnDetail(ar)},
);

/// The photo library, answering with the sample photo (Figma 23 shows one
/// attached).
Override returnPhotoPickerOverride() => returnPhotoPickerProvider
    .overrideWithValue(FakeReturnPhotoPicker(photos: [kGreenPhoto]));

// ---------------------------------------------------------- E24 addresses ---

/// The account's address book in memory: the saved addresses, and the store's
/// `address_label` options (Home / Work / Other) in the store view's language.
class AddressBook extends FakeAccountRepository {
  AddressBook(this.addresses, {this.locale = 'en'});

  List<CustomerAddress> addresses;
  final String locale;
  final List<({int id, bool defaultShipping})> updates = [];
  final List<int> deleted = [];
  final List<CustomerAddress> created = [];

  @override
  Future<List<CustomerAddress>> fetchAddresses() async => addresses;

  @override
  Future<void> updateAddress(int id, CustomerAddress address) async {
    updates.add((id: id, defaultShipping: address.defaultShipping));
  }

  @override
  Future<void> deleteAddress(int id) async {
    deleted.add(id);
  }

  @override
  Future<void> createAddress(CustomerAddress address) async {
    created.add(address);
  }

  @override
  Future<List<({String value, String label})>>
  fetchAddressLabelOptions() async => locale == 'ar'
      ? const [
          (value: '1', label: 'المنزل'),
          (value: '2', label: 'العمل'),
          (value: '3', label: 'آخر'),
        ]
      : const [
          (value: '1', label: 'Home'),
          (value: '2', label: 'Work'),
          (value: '3', label: 'Other'),
        ];
}

/// Figma 24: Sara's two saved addresses, the first the default.
List<CustomerAddress> savedAddresses(String locale) {
  final ar = locale == 'ar';
  return [
    CustomerAddress(
      id: 1,
      firstName: ar ? 'سارة' : 'Sara',
      lastName: ar ? 'أحمد' : 'Ahmed',
      telephone: '+971501234567',
      apartment: ar ? 'شقة 1204' : 'Apt 1204',
      street: ar ? 'مارينا جيت 2' : 'Marina Gate 2',
      city: ar ? 'دبي مارينا' : 'Dubai Marina',
      region: ar ? 'دبي' : 'Dubai',
      defaultShipping: true,
      labelText: ar ? 'المنزل' : 'Home',
    ),
    CustomerAddress(
      id: 2,
      firstName: ar ? 'سارة' : 'Sara',
      lastName: ar ? 'أحمد' : 'Ahmed',
      telephone: '+971501234567',
      street: ar ? 'مكتب 802، مبنى 4' : 'Office 802, Building 4',
      city: ar ? 'مدينة دبي للإنترنت' : 'Dubai Internet City',
      region: ar ? 'دبي' : 'Dubai',
      labelText: ar ? 'العمل' : 'Office',
    ),
  ];
}

// ------------------------------------------------------------ E25 wishlist ---

/// A wishlist holding [products], with the repository's own removal.
class SavedWishlist extends FakeWishlistRepository {
  SavedWishlist(List<Product> products)
    : _data = WishlistData(
        id: 'wl-1',
        entries: [
          for (final p in products)
            WishlistEntry(id: 'item-${p.sku}', product: p),
        ],
      );

  WishlistData _data;

  @override
  Future<WishlistData?> fetchWishlist() async => _data;

  @override
  Future<WishlistData> removeItems(
    String wishlistId,
    List<String> itemIds,
  ) async => _data = WishlistData(
    id: wishlistId,
    entries: _data.entries.where((e) => !itemIds.contains(e.id)).toList(),
  );
}

Product _wishProduct(
  String sku,
  String name,
  String store,
  double rating,
  int reviews,
  double price, {
  double? was,
}) => Product(
  sku: sku,
  name: name,
  urlKey: sku,
  sellerName: store,
  sellerCode: store.toLowerCase().replaceAll(' ', ''),
  sellerKnown: true,
  ratingSummary: rating * 20,
  reviewCount: reviews,
  regularPrice: Money(amount: was ?? price, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
);

/// Figma 25: six saved items from three stores.
List<Product> wishlistProducts(String locale) {
  final ar = locale == 'ar';
  return [
    _wishProduct(
      'sofa',
      ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
      'MIA CO',
      4.6,
      18,
      425,
      was: 500,
    ),
    _wishProduct(
      'dress',
      ar
          ? 'فستان صدر طباعة الأزهار رباط مشد خصر'
          : 'Floral Print Corset-Waist Tie Dress',
      'loly store',
      4.3,
      27,
      50,
    ),
    _wishProduct(
      'chair',
      ar ? 'كرسي هزاز عنابي' : 'Burgundy Rocking Chair',
      'MIA CO',
      4.7,
      21,
      180,
    ),
    _wishProduct(
      'milk',
      ar ? 'حليب كامل الدسم جهينة 1 لتر' : 'Juhayna Full Cream Milk 1 L',
      'walmart',
      4.7,
      96,
      35,
    ),
    _wishProduct(
      'polo',
      ar ? 'قميص بولو' : 'Polo Shirt',
      'loly store',
      4.5,
      33,
      13,
    ),
    _wishProduct(
      'desk',
      ar ? 'مكتب مدير عصري 160 سم' : 'Modern Executive Desk 160 cm',
      'MIA CO',
      4.5,
      7,
      350,
    ),
  ];
}

// ------------------------------------------------------- E26 track order ---

/// Answers the guest lookup with [order]; nothing else of the account is read.
class GuestOrderRepo implements AccountRepository {
  GuestOrderRepo({required this.order});

  final CustomerOrder order;

  /// What the form sent.
  final List<({String number, String email, String lastname})> lookups = [];

  @override
  Future<CustomerOrder> fetchGuestOrder({
    required String number,
    required String email,
    required String lastname,
  }) async {
    lookups.add((number: number, email: email, lastname: lastname));
    return order;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Order HM-100248 as a guest finds it: loly store's dress shipped, MIA CO's
/// sofa and chair still being prepared.
CustomerOrder guestOrder(String locale) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  return CustomerOrder(
    number: 'HM-100248',
    status: ar ? 'في الطريق إليك' : 'Out for delivery',
    date: '2026-09-28 10:42:00',
    token: 'tok-248',
    placedAsGuest: true,
    invoiceCount: 1,
    shipmentCount: 1,
    total: aedMoney(553),
    lines: [
      OrderLine(name: 'Dress', quantity: 1, seller: loly, uid: 'a'),
      OrderLine(name: 'Sofa', quantity: 1, seller: mia, uid: 'b'),
      OrderLine(name: 'Chair', quantity: 2, seller: mia, uid: 'c'),
    ],
    packages: [
      OrderPackage(
        seller: loly,
        statusCode: 'processing',
        statusLabel: 'Out for delivery',
        state: 'processing',
        itemUids: const ['a'],
        shipments: const [OrderPackageShipment(id: 's', number: '31')],
      ),
      OrderPackage(
        seller: mia,
        statusCode: 'new',
        statusLabel: 'Processing',
        state: 'new',
        itemUids: const ['b', 'c'],
      ),
    ],
  );
}
