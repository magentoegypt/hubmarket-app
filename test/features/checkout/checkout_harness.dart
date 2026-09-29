import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/address/regions.dart';
import 'package:hubmarket_app/core/config/backend_capabilities.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/data/address_rules.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/checkout_screen.dart';
import 'package:hubmarket_app/features/checkout/presentation/screens/order_success_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';

/// Shared set-up for the checkout widget and render tests: a three-line cart,
/// the two shipping methods of Figma 17, and the screen mounted in a router
/// that also knows Order placed.

Money aed(double amount) => Money(amount: amount, currency: 'AED');

/// The cart of Figma 18b: 4 items, AED 543.
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

/// Serves [checkoutCart] until an order consumes it.
class CheckoutCartRepository extends FakeCartRepository {
  @override
  Future<Cart> getCart(String cartId) async => checkoutCart(cartId);
}

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

/// A backend offering cash on delivery next to an online method checkout
/// must leave out.
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

const kSavedAddress = CustomerAddress(
  id: 7,
  firstName: 'Sara',
  lastName: 'Ahmed',
  telephone: '+971501234567',
  street: 'Marina Gate 2',
  apartment: 'Apt 1204',
  city: 'Dubai',
  region: 'Dubai',
  defaultShipping: true,
  labelText: 'Home',
);

/// The checkout screen in a router with Order placed and stand-ins for the
/// routes it leaves to. [signedIn] runs the customer path with
/// [kSavedAddress] in the address book.
Widget checkoutHarness({
  required String locale,
  required FakeCheckoutRepository repository,
  bool signedIn = false,
  bool darkMode = false,
  BackendCapabilities capabilities = BackendCapabilities.hubMarket,
  GlobalKey? boundary,
  CartRepository? cartRepository,
}) {
  final cache = FakeLocalCache()..writeString('guest_cart_id', 'guest-1');
  final router = GoRouter(
    initialLocation: AppRoutes.checkout,
    routes: [
      GoRoute(
        path: AppRoutes.checkout,
        builder: (_, __) => const CheckoutScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderSuccess,
        redirect: (_, state) =>
            state.extra is OrderPlacedArgs ? null : AppRoutes.home,
        builder: (_, state) =>
            OrderSuccessScreen(args: state.extra! as OrderPlacedArgs),
      ),
      for (final path in [
        AppRoutes.home,
        AppRoutes.cart,
        AppRoutes.orders,
        AppRoutes.signIn,
        AppRoutes.forgotPassword,
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('route $path')),
        ),
    ],
  );
  final app = MaterialApp.router(
    routerConfig: router,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    darkTheme: AppTheme.dark(locale),
    themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
    locale: Locale(locale),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'customer-token' : null),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(
        cartRepository ?? CheckoutCartRepository(),
      ),
      checkoutRepositoryProvider.overrideWithValue(repository),
      backendCapabilitiesProvider.overrideWithValue(capabilities),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      regionsProvider.overrideWith((ref) async => uaeFallbackRegions),
      postcodeRequiredProvider.overrideWith((ref) async => false),
      addressesProvider.overrideWith(
        (ref) async => signedIn ? const [kSavedAddress] : const [],
      ),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// Types the guest's contact and address (Figma 17a) into the form.
Future<void> fillGuestAddress(WidgetTester tester) async {
  final fields = find.byType(TextFormField);
  Future<void> type(int index, String text) async {
    await tester.ensureVisible(fields.at(index));
    await tester.enterText(fields.at(index), text);
  }

  await type(0, 'sara.ahmed@gmail.com');
  await type(1, 'Sara Ahmed');
  await type(2, '501234567');
  await type(3, 'Marina Gate 2');
  await type(4, 'Apt 1204');
  final emirate = find.byType(DropdownButtonFormField<int>);
  await tester.ensureVisible(emirate);
  await tester.pumpAndSettle();
  await tester.tap(emirate);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Dubai').last);
  await tester.pumpAndSettle();
}

/// Taps a footer / card action by its text and settles.
Future<void> tapText(WidgetTester tester, String text) async {
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

/// The same fonts the app bundles, plus Material Icons from the SDK, so the
/// PNG renders read like the device.
Future<void> loadCheckoutFonts() => loadAppFonts();

/// Writes what [boundary] shows to `build/test_screens/<name>.png` — a visual
/// record for review against the Figma frames; nothing is asserted on it.
Future<void> capture(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  await tester.runAsync(() async {
    final object =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await object.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}
