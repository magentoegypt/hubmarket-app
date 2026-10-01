import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/address/regions.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/util/launch.dart';
import 'package:hubmarket_app/features/account/data/address_rules.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/address_form_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/addresses_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/guest_track_order_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_tracking_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/orders_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/my_returns_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/request_return_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/return_detail_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_photos.dart';
import 'package:hubmarket_app/features/wishlist/presentation/screens/wishlist_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../test/support/fakes.dart';
import '../../test/support/marketplace_fakes.dart';
import '../../test/support/order_package_fixtures.dart';
import '../../test/support/returns_fakes.dart';
import 'audit_scene.dart';
import 'harness.dart';
import 'orders_fixtures.dart';

/// Orders, returns, addresses and wishlist: E21 Orders, E21b Cancel order,
/// E22 Order detail, E23 Return request, E23b My returns, E23c Return detail,
/// E24 Addresses, E24b Address form, E25 Wishlist, E26 Track order.
///
/// E21 and E21b are the reference scenes (ported from
/// test/features/account/audit_orders_list_test.dart); the rest follow the
/// same pattern, their fixtures in orders_fixtures.dart (copied from the widget
/// test that renders the frame, named in that file).
List<AuditScene> scenes() => [
  AuditScene(
    frame: 'E21_orders',
    name: 'default',
    screen: (_) => const OrdersScreen(),
    setup: (locale) => AuditSetup(
      account: FakeAccountRepository(orders: _orders(locale)),
      returns: FakeReturnsRepository(
        summaries: [_openReturn(seller('loly', 'loly store'))],
      ),
    ),
  ),
  // Figma 21b: "Cancel order" on the first card opens the sheet over the list.
  AuditScene(
    frame: 'E21b_cancel_order',
    name: 'default',
    screen: (_) => const OrdersScreen(),
    setup: (locale) => AuditSetup(
      account: FakeAccountRepository(orders: _orders(locale)),
      returns: FakeReturnsRepository(),
    ),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tester.tap(find.text(l10n.orderCancelAction));
      await pumpFor(tester, 500);
    },
  ),

  // ---- E22 Order detail (1562 px: scrolls 2) ------------------------------
  // audit_22_order_detail: one card per store, each with its own timeline.
  AuditScene(
    frame: 'E22_order_detail',
    name: 'default',
    screen: (locale) => OrderDetailScreen(order: detailOrder(locale)),
    setup: (_) => AuditSetup(overrides: detailOverrides()),
    scrolls: 2,
  ),
  // p3_22_order: an order the server did not split, the lines grouped by their
  // store (the marketplace harness: store features off, so no cancellation).
  // Pushed over Home like the real page; that harness mounts it as the root.
  AuditScene(
    frame: 'E22_order_detail',
    name: 'by_store',
    screen: (locale) => OrderDetailScreen(order: byStoreOrder(locale)),
    setup: (_) => AuditSetup(
      features: StoreFeatures.none,
      overrides: [storeTimezoneProvider.overrideWith((ref) async => '')],
    ),
    scrolls: 2,
  ),

  // ---- E23 Request a return (1086 px: scrolls 1) --------------------------
  // The frame's state: a reason chosen, the package opened, a photo attached.
  AuditScene(
    frame: 'E23_return_request',
    name: 'default',
    screen: (locale) =>
        RequestReturnScreen(order: returnableOrder(locale == 'ar')),
    setup: (locale) => AuditSetup(
      returns: returnsRepo(locale == 'ar'),
      overrides: [returnPhotoPickerOverride()],
    ),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      final reason = returnConfig(locale == 'ar').reasons.first.label;
      await tapVisible(tester, find.text(l10n.returnsChooseReason));
      await tapVisible(tester, find.text(reason));
      await tapVisible(tester, find.text(l10n.returnsAnswerYes));
      await tapVisible(tester, find.byType(ReturnAddPhotoTile));
      await tapVisible(tester, find.text(l10n.returnsChoosePhotos));
      // The state of the frame was reached: the reason shows in its field and
      // the picked photo sits beside the Add tile.
      expect(find.text(reason), findsOneWidget);
      expect(find.byType(ReturnPhotoTile), findsOneWidget);
      await scrollToTop(tester);
    },
    scrolls: 1,
  ),
  // 23b My returns: awaiting the store, refunded, rejected.
  AuditScene(
    frame: 'E23b_my_returns',
    name: 'default',
    screen: (_) => const MyReturnsScreen(),
    setup: (locale) => AuditSetup(returns: returnsRepo(locale == 'ar')),
  ),
  // 23c Return detail: the customer's message and loly store's answer.
  AuditScene(
    frame: 'E23c_return_detail',
    name: 'default',
    screen: (_) => const ReturnDetailScreen(returnId: 31),
    setup: (locale) => AuditSetup(returns: returnsRepo(locale == 'ar')),
  ),

  // ---- E24 Saved addresses, E24b Address form -----------------------------
  AuditScene(
    frame: 'E24_addresses',
    name: 'default',
    screen: (_) => const AddressesScreen(),
    setup: (locale) => AuditSetup(
      account: AddressBook(savedAddresses(locale), locale: locale),
    ),
  ),
  // 24b (1198 px: scrolls 1), filled the way the frame shows it. The UAE has no
  // postcodes (the frame has no such field), and the emirates come from
  // `uaeFallbackRegions`, which the live store also ends up with (it defines
  // no UAE regions): no request is made for them.
  AuditScene(
    frame: 'E24b_address_form',
    name: 'default',
    screen: (_) => const AddressFormScreen(),
    setup: (locale) => AuditSetup(
      account: AddressBook(const [], locale: locale),
      overrides: [
        postcodeRequiredProvider.overrideWith((ref) async => false),
        regionsProvider.overrideWith((ref) async => uaeFallbackRegions),
      ],
    ),
    act: (tester, locale) async {
      final ar = locale == 'ar';
      final l10n = lookupAppLocalizations(Locale(locale));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), ar ? 'سارة أحمد' : 'Sara Ahmed');
      await tester.enterText(fields.at(1), '+971 50 123 4567');
      await tapVisible(tester, find.byIcon(HubIcons.globe));
      await tapVisible(tester, find.text(ar ? 'دبي' : 'Dubai').last);
      await tester.enterText(
        fields.at(2),
        ar ? 'مارينا جيت 2' : 'Marina Gate 2',
      );
      await tester.enterText(fields.at(3), '1204');
      await tapVisible(tester, find.text(ar ? 'المنزل' : 'Home').last);
      await tapVisible(tester, find.text(l10n.addressDefaultShipping));
      // The emirate picked in the sheet shows in its field; the sheet is shut.
      expect(find.text(ar ? 'دبي' : 'Dubai'), findsOneWidget);
      await unfocus(tester);
      await scrollToTop(tester);
    },
    scrolls: 1,
  ),

  // ---- E25 Wishlist: a tab root, six saved items from three stores --------
  AuditScene(
    frame: 'E25_wishlist',
    name: 'default',
    pushed: false,
    screen: (_) => const WishlistScreen(),
    setup: (locale) =>
        AuditSetup(wishlist: SavedWishlist(wishlistProducts(locale))),
    scrolls: 1,
  ),

  // ---- E26 Track order -----------------------------------------------------
  // audit_26_track_order: a guest (signed OUT) fills the form in and presses
  // Find order; the order it finds shows under the form.
  AuditScene(
    frame: 'E26_track_order',
    name: 'default',
    signedIn: false,
    screen: (_) => const GuestTrackOrderScreen(),
    setup: (locale) =>
        AuditSetup(account: GuestOrderRepo(order: guestOrder(locale))),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'HM-100248');
      await tester.enterText(fields.at(1), locale == 'ar' ? 'أحمد' : 'Ahmed');
      await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
      await tapVisible(tester, find.text(l10n.guestTrackSubmit), settleMs: 800);
      // The lookup answered: its order shows under the form.
      expect(find.text(l10n.guestTrackViewOrder), findsOneWidget);
      await scrollToTop(tester);
    },
    scrolls: 1,
  ),
  // The form before a lookup (audit_26_track_order_empty_en), signed out.
  AuditScene(
    frame: 'E26_track_order',
    name: 'form',
    signedIn: false,
    screen: (_) => const GuestTrackOrderScreen(),
    setup: (locale) =>
        AuditSetup(account: GuestOrderRepo(order: guestOrder(locale))),
  ),
  // p31_26_packages: the tracking page of an order split by store (a guest's,
  // as after checkout), the harness of order_screens_harness.dart: store
  // features off, "Track parcel" opens nothing.
  AuditScene(
    frame: 'E26_track_order',
    name: 'packages',
    signedIn: false,
    screen: (locale) => OrderTrackingScreen(
      order: packagedOrder(locale: locale, placedAsGuest: true),
    ),
    setup: (_) => AuditSetup(
      features: StoreFeatures.none,
      overrides: [
        storeTimezoneProvider.overrideWith((ref) async => ''),
        externalUriLauncherProvider.overrideWithValue((uri) async => true),
      ],
    ),
    scrolls: 1,
  ),
];

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

OrderPackage _package(
  HmSellerSummary store,
  String label,
  String state,
  List<String> uids, {
  bool shipped = false,
}) => OrderPackage(
  seller: store,
  statusCode: state,
  statusLabel: label,
  state: state,
  itemUids: uids,
  shipments: [
    if (shipped) const OrderPackageShipment(id: 's1', number: '000000031'),
  ],
);

OrderLine _line(String name, String uid, HmSellerSummary store) => OrderLine(
  name: name,
  quantity: 1,
  sku: 'SKU-$uid',
  seller: store,
  uid: uid,
);

List<CustomerOrder> _orders(String locale) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  final walmart = seller('walmart', ar ? 'وول مارت' : 'walmart');
  return [
    // Out for delivery at loly store, being prepared at MIA CO.
    CustomerOrder(
      number: 'HM-100248',
      status: ar ? 'قيد التنفيذ' : 'Processing',
      date: '2026-09-28 10:42:00',
      id: 'MjQ4',
      availableActions: const {'CANCEL'},
      invoiceCount: 1,
      total: _aed(553),
      lines: [
        _line('Floral Print Corset-Waist Tie Dress', 'a', loly),
        _line('Corner Sofa Bed', 'b', mia),
        _line('Dining Chair with Gold Metal Legs', 'c', mia),
      ],
      packages: [
        _package(
          loly,
          ar ? 'في الطريق إليك' : 'Out for delivery',
          'processing',
          const ['a'],
          shipped: true,
        ),
        _package(mia, ar ? 'قيد التجهيز' : 'Processing', 'new', const [
          'b',
          'c',
        ]),
      ],
    ),
    // Delivered by walmart.
    CustomerOrder(
      number: 'HM-100197',
      status: ar ? 'مكتمل' : 'Complete',
      date: '2026-09-14 09:10:00',
      id: 'MTk3',
      availableActions: const {'REORDER'},
      invoiceCount: 1,
      shipmentCount: 1,
      total: _aed(98),
      lines: [
        _line('Tuna', 'd', walmart),
        _line('Cola', 'e', walmart),
        _line('Water', 'f', walmart),
      ],
      packages: [
        _package(walmart, ar ? 'تم التوصيل' : 'Delivered', 'complete', const [
          'd',
          'e',
          'f',
        ]),
      ],
    ),
    // A return open on it.
    CustomerOrder(
      number: 'HM-100150',
      status: ar ? 'مكتمل' : 'Complete',
      date: '2026-09-20 18:30:00',
      id: 'MTUw',
      invoiceCount: 1,
      shipmentCount: 1,
      total: _aed(43),
      lines: [_line('Short Square-Neck T-Shirt', 'g', loly)],
      packages: [
        _package(loly, ar ? 'تم التوصيل' : 'Delivered', 'complete', const [
          'g',
        ]),
      ],
    ),
  ];
}

ReturnSummary _openReturn(HmSellerSummary store) => ReturnSummary(
  id: 31,
  number: 'R-000031',
  orderNumber: 'HM-100150',
  createdAt: '2026-09-24T09:00:00Z',
  statusCode: 'pending',
  statusLabel: 'Awaiting store',
  itemCount: 1,
  seller: store,
);
