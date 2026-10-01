import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/address/regions.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/data/address_rules.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';

import '../../test/support/fakes.dart';
import '../../test/support/hubapp_fakes.dart';
import '../../test/support/marketplace_fakes.dart' show seller;
import '../../test/support/store_credit_fakes.dart';
import 'harness.dart';

/// Fixtures of the cart and checkout scenes (scenes_checkout.dart), copied from
/// the widget tests that render the frames — test/features/checkout/
/// checkout_harness.dart (17 / 17a / 18 / 18b / 19), test/features/marketplace/
/// marketplace_render_test.dart + marketplace_harness.dart (16) and
/// test/features/cart/cart_screen_harness.dart (S1).

Money aed(double amount) => Money(amount: amount, currency: 'AED');

/// Store and product names as each store view serves them.
({String loly, String mia, String dress, String sofa, String chair}) names(
  String locale,
) => locale == 'ar'
    ? (
        loly: 'متجر لولي',
        mia: 'ميا كو',
        dress: 'فستان صدر طباعة الأزهار رباط مشد خصر',
        sofa: 'كنبة سرير ركنه',
        chair: 'كرسي طعام بارجل ذهبية معدنية',
      )
    : (
        loly: 'loly store',
        mia: 'MIA CO',
        dress: 'Floral Print Corset-Waist Tie Dress',
        sofa: 'Corner Sofa Bed',
        chair: 'Dining Chair with Gold Metal Legs',
      );

// ---------------------------------------------------------------------------
// Carts
// ---------------------------------------------------------------------------

/// Figma 16: four items from two stores (MIA CO sells the sofa and the chairs,
/// loly store the dress), the delivery fee chosen at checkout in the totals.
Cart cartByStore(String locale, String id) {
  final n = names(locale);
  final mia = seller('mia', n.mia);
  final loly = seller('loly', n.loly);
  return Cart(
    id: id,
    totalQuantity: 4,
    items: [
      CartItem(
        uid: 'i-sofa',
        sku: 'SOFA',
        name: n.sofa,
        quantity: 1,
        unitPrice: aed(425),
        originalUnitPrice: aed(500),
        rowTotal: aed(425),
        options: const ['Colour: Teal'],
        seller: mia,
      ),
      CartItem(
        uid: 'i-chair',
        sku: 'CHAIR',
        name: n.chair,
        quantity: 2,
        unitPrice: aed(34),
        originalUnitPrice: aed(40),
        rowTotal: aed(68),
        options: const ['Colour: Sky blue'],
        seller: mia,
      ),
      CartItem(
        uid: 'i-dress',
        sku: 'DRESS',
        name: n.dress,
        quantity: 1,
        unitPrice: aed(50),
        rowTotal: aed(50),
        options: const ['Size: M'],
        seller: loly,
      ),
    ],
    // Delivery chosen at checkout: 543 + 10.
    totals: CartTotals(
      subtotal: aed(543),
      shipping: aed(10),
      grandTotal: aed(553),
    ),
  );
}

/// The cart of Figma 18b without HubApp (Build 1): 4 items, AED 543, no store
/// on any line.
Cart checkoutCart(String id) => Cart(
  id: id,
  totalQuantity: 4,
  items: [
    CartItem(
      uid: 'i-sofa',
      sku: 'SOFA',
      name: 'Corner Sofa Bed',
      quantity: 1,
      unitPrice: aed(425),
      rowTotal: aed(425),
      options: const ['Colour: Teal'],
    ),
    CartItem(
      uid: 'i-chair',
      sku: 'CHAIR',
      name: 'Dining Chair with Gold Metal Legs',
      quantity: 2,
      unitPrice: aed(34),
      rowTotal: aed(68),
    ),
    CartItem(
      uid: 'i-dress',
      sku: 'DRESS',
      name: 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      unitPrice: aed(50),
      rowTotal: aed(50),
      options: const ['Size: M'],
    ),
  ],
  totals: CartTotals(subtotal: aed(543), grandTotal: aed(553)),
);

/// [checkoutCart] as HubApp serves it: each line with its store, MIA CO selling
/// the sofa and the chairs and loly store the dress (Figma 17 - 19), the names
/// as the [locale]'s store view gives them.
Cart checkoutSellerCart(String id, {String locale = 'en'}) {
  final n = names(locale);
  final mia = seller('mia', n.mia);
  final loly = seller('loly', n.loly);
  return Cart(
    id: id,
    totalQuantity: 4,
    items: [
      CartItem(
        uid: 'i-sofa',
        sku: 'SOFA',
        name: n.sofa,
        quantity: 1,
        unitPrice: aed(425),
        rowTotal: aed(425),
        seller: mia,
      ),
      CartItem(
        uid: 'i-chair',
        sku: 'CHAIR',
        name: n.chair,
        quantity: 2,
        unitPrice: aed(34),
        rowTotal: aed(68),
        seller: mia,
      ),
      CartItem(
        uid: 'i-dress',
        sku: 'DRESS',
        name: n.dress,
        quantity: 1,
        unitPrice: aed(50),
        rowTotal: aed(50),
        seller: loly,
      ),
    ],
    totals: CartTotals(subtotal: aed(543), grandTotal: aed(553)),
  );
}

/// Serves one fixed [cart], whatever id it is asked for.
class FixedCartRepository extends FakeCartRepository {
  FixedCartRepository(this.cart);

  final Cart Function(String id) cart;

  @override
  Future<Cart> getCart(String cartId) async => cart(cartId);
}

/// The trust block as the cart frame's ticks read (titles only).
String cartTrustBlock(String locale) => locale == 'ar'
    ? '<div class="hm-trust">'
          '<div class="hm-trust__item"><span class="hm-trust__title">دفع آمن بتشفير SSL</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">طلبات من عدة بائعين في عملية دفع واحدة</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">إرجاع خلال 14 يومًا لمعظم المنتجات</span></div>'
          '</div>'
    : '<div class="hm-trust">'
          '<div class="hm-trust__item"><span class="hm-trust__title">Secure checkout with SSL encryption</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">Orders from multiple vendors in one checkout</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">14-day returns on most items</span></div>'
          '</div>';

// ---------------------------------------------------------------------------
// Checkout
// ---------------------------------------------------------------------------

const kShippingMethods = <ShippingMethodOption>[
  ShippingMethodOption(
    carrierCode: 'flatrate',
    methodCode: 'flatrate',
    title: 'Standard delivery',
    detail: '2–4 working days',
    amount: Money(amount: 10, currency: 'AED'),
  ),
  ShippingMethodOption(
    carrierCode: 'express',
    methodCode: 'express',
    title: 'Express delivery',
    detail: 'Next working day',
    amount: Money(amount: 35, currency: 'AED'),
  ),
];

/// A backend offering cash on delivery next to an online method checkout must
/// leave out. [registeredEmail] is an address the store says has an account.
FakeCheckoutRepository checkoutRepository({String? registeredEmail}) =>
    FakeCheckoutRepository(
      shippingMethods: kShippingMethods,
      paymentMethods: const [
        PaymentMethodOption(code: 'cashondelivery', title: 'Cash on delivery'),
        PaymentMethodOption(
          code: 'tabby_installments',
          title: 'Pay in 4 with Tabby',
          isOnline: true,
        ),
      ],
      grandTotal: aed(553),
      orderResult: const PlaceOrderResult(orderNumber: '000000248'),
    )..registeredEmails = {if (registeredEmail != null) registeredEmail};

/// What checkout offers once the order is placed: the cash on delivery the
/// payment step pre-selects.
const kCashOnDelivery = PaymentMethodOption(
  code: 'cashondelivery',
  title: 'Cash on delivery',
);

const kSavedAddress = CustomerAddress(
  id: 7,
  firstName: 'Sara',
  lastName: 'Ahmed',
  telephone: '+971501234567',
  street: 'Marina Gate 2',
  apartment: 'Apt 1204',
  city: 'Dubai Marina',
  region: 'Dubai',
  defaultShipping: true,
  labelText: 'Home',
);

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// The cache of a device that has a guest cart (`guest-1`): the cart tab and
/// checkout load it from there when nobody is signed in.
Override guestCartCache() => localCacheProvider.overrideWithValue(
  FakeLocalCache()..writeString('guest_cart_id', 'guest-1'),
);

/// The clients the audit harness does not fake (it fakes the POST one): every
/// request fails at once, as in the widget tests, so no scene reaches the
/// server through the public GET client or the token-less one.
List<Override> offlineClients() => [
  publicGraphqlClientProvider.overrideWithValue(fakeHubAppClient(const {})),
  guestGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
];

/// Store credit as the payment step (Figma 18, "Use my credit - AED 120.00
/// available") reads it: AED 120 on a cart that costs more, none used.
Override storeCreditOffered() =>
    storeCreditRepositoryProvider.overrideWithValue(
      FakeStoreCreditRepository(cartCredit: sampleCartCredit()),
    );

/// The cart tab: [cart] on this device's guest cart, the store's free-shipping
/// threshold when [freeShipping] is given, and the storefront's trust block as
/// [cmsBlocks] (the cart's ticks come from it).
List<Override> cartTabOverrides({
  required CartRepository cart,
  double? freeShipping,
  Map<String, String>? cmsBlocks,
}) => [
  guestCartCache(),
  cartRepositoryProvider.overrideWithValue(cart),
  freeShippingThresholdProvider.overrideWith((ref) async => freeShipping),
  if (cmsBlocks != null)
    homeCmsBlocksProvider.overrideWith((ref) async => cmsBlocks),
  ...offlineClients(),
];

/// Checkout (Figma 17 - 19): [cart], a [checkoutRepository] with the two
/// shipping methods and cash on delivery, the UAE emirates, no postcode, and the
/// address book of a signed-in customer ([kSavedAddress]; none for a guest).
/// With [hubApp], the store's AED 600 free-shipping threshold and AED 120 of
/// store credit to use.
List<Override> checkoutOverrides({
  required CartRepository cart,
  bool signedIn = true,
  bool hubApp = false,
  String? registeredEmail,
}) => [
  guestCartCache(),
  cartRepositoryProvider.overrideWithValue(cart),
  checkoutRepositoryProvider.overrideWithValue(
    checkoutRepository(registeredEmail: registeredEmail),
  ),
  regionsProvider.overrideWith((ref) async => uaeFallbackRegions),
  postcodeRequiredProvider.overrideWith((ref) async => false),
  addressesProvider.overrideWith(
    (ref) async => signedIn ? const [kSavedAddress] : const <CustomerAddress>[],
  ),
  if (hubApp) ...[
    freeShippingThresholdProvider.overrideWith((ref) async => 600),
    storeCreditOffered(),
  ],
  ...offlineClients(),
];

// ---------------------------------------------------------------------------
// Taps
// ---------------------------------------------------------------------------

/// Taps a footer / card action by its text and lets the screen settle.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await pumpFor(tester, 500);
}

/// Back to the top of the page: typing into the lower fields of a form scrolls
/// it down, and the frame starts at the top (the harness's `scrolls` then walk
/// down from there).
Future<void> scrollToTop(WidgetTester tester) async {
  for (final element in find.byType(Scrollable).evaluate()) {
    if (element is! StatefulElement) continue;
    final state = element.state;
    if (state is! ScrollableState) continue;
    final axis = state.axisDirection;
    if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
    final position = state.position;
    if (position.hasContentDimensions) {
      position.jumpTo(position.minScrollExtent);
    }
  }
  await pumpFor(tester, 300);
}

/// Types the guest's contact and address (Figma 17a) into the form: the email,
/// full name, mobile number, then - after the emirate picker - area, street &
/// building and apartment / villa. Leaving the email field asks the store
/// whether it has an account (the frame's "You already have an account" card).
Future<void> fillGuestAddress(WidgetTester tester) async {
  final fields = find.byType(TextField);
  Future<void> type(int index, String text) async {
    await tester.ensureVisible(fields.at(index));
    await tester.enterText(fields.at(index), text);
  }

  await type(0, 'sara.ahmed@gmail.com');
  await type(1, 'Sara Ahmed');
  await type(2, '+971 50 123 4567');
  await type(3, 'Dubai Marina');
  await type(4, 'Marina Gate 2');
  await type(5, '1204');
  final emirate = find.byType(DropdownButtonFormField<int>);
  await tester.ensureVisible(emirate);
  await pumpFor(tester, 400);
  await tester.tap(emirate);
  await pumpFor(tester, 500);
  await tester.tap(find.text('Dubai').last);
  await pumpFor(tester, 500);
}
