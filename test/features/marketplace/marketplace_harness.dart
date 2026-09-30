import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/web_view_screen.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';

/// Shared set-up for the P3 marketplace screens (Figma 14 / 14b / 16 / 22):
/// the screen in a router that also knows the store page and the in-app
/// browser, HubApp faked as [hubApp], and the public client answering
/// [publicAnswers] by operation name.

Money aed(double amount) => Money(amount: amount, currency: 'AED');

/// Serves one canned [ProductDetail].
class DetailRepository extends FakeCatalogRepository {
  DetailRepository(this.detail);
  final ProductDetail detail;

  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async => detail;
}

/// Serves [cart] until a change replaces it.
class CannedCartRepository extends FakeCartRepository {
  CannedCartRepository(this.cart);
  final Cart cart;

  @override
  Future<Cart> getCart(String cartId) async => cart;
}

/// Figma 16: four items from two stores.
Cart twoStoreCart(String id) => Cart(
  id: id,
  totalQuantity: 4,
  items: [
    CartItem(
      uid: 'i-sofa',
      sku: 'SOFA',
      name: 'Corner Sofa Bed',
      quantity: 1,
      unitPrice: aed(425),
      originalUnitPrice: aed(500),
      rowTotal: aed(425),
      options: const ['Colour: Teal'],
      seller: seller('mia', 'MIA CO'),
    ),
    CartItem(
      uid: 'i-chair',
      sku: 'CHAIR',
      name: 'Dining Chair with Gold Metal Legs',
      quantity: 2,
      unitPrice: aed(34),
      originalUnitPrice: aed(40),
      rowTotal: aed(68),
      options: const ['Colour: Sky blue'],
      seller: seller('mia', 'MIA CO'),
    ),
    CartItem(
      uid: 'i-dress',
      sku: 'DRESS',
      name: 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      unitPrice: aed(50),
      rowTotal: aed(50),
      options: const ['Size: M'],
      seller: seller('loly', 'loly store'),
    ),
  ],
  // Delivery chosen at checkout: 543 + 10.
  totals: CartTotals(
    subtotal: aed(543),
    shipping: aed(10),
    grandTotal: aed(553),
  ),
);

/// Figma 22: an order of three lines from two stores.
CustomerOrder twoStoreOrder({bool withSellers = true}) => CustomerOrder(
  number: 'HM-100248',
  status: 'Processing',
  date: '2026-09-28 10:42:00',
  id: 'MjQ4',
  total: aed(553),
  subtotal: aed(543),
  shippingAmount: aed(10),
  paymentMethodName: 'Cash on delivery',
  lines: [
    OrderLine(
      name: 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      price: aed(50),
      sku: 'DRESS',
      seller: withSellers ? seller('loly', 'loly store') : null,
    ),
    OrderLine(
      name: 'Corner Sofa Bed',
      quantity: 1,
      price: aed(425),
      sku: 'SOFA',
      seller: withSellers ? seller('mia', 'MIA CO') : null,
    ),
    OrderLine(
      name: 'Dining Chair with Gold Metal Legs',
      quantity: 2,
      price: aed(34),
      sku: 'CHAIR',
      seller: withSellers ? seller('mia', 'MIA CO') : null,
    ),
  ],
);

/// The screen at [location] in a router with every route it may leave to.
/// [storeRoute] false leaves `/store/:code` out, as a build without the
/// stores screens.
Widget marketplaceHarness({
  required String locale,
  required String location,
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  Map<String, Object> publicAnswers = const {},
  FakeHubAppClient? publicClient,
  CartRepository? cartRepository,
  CatalogRepository? catalogRepository,
  CustomerOrder? order,
  bool storeRoute = true,
  bool signedIn = false,
  StoreCreditRepository? storeCredit,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) =>
            ProductDetailScreen(urlKey: state.pathParameters['urlKey']!),
      ),
      GoRoute(path: AppRoutes.cart, builder: (_, __) => const CartScreen()),
      if (order != null)
        GoRoute(
          path: AppRoutes.orderDetail,
          builder: (_, __) => OrderDetailScreen(order: order),
        ),
      if (storeRoute)
        GoRoute(
          path: '/store/:code',
          builder: (_, state) => Scaffold(
            body: Text('store page ${state.pathParameters['code']}'),
          ),
        ),
      GoRoute(
        path: AppRoutes.webview,
        builder: (_, state) =>
            Scaffold(body: Text('web ${(state.extra! as WebViewArgs).url}')),
      ),
      for (final path in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.checkout,
        AppRoutes.search,
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text(path)),
        ),
    ],
  );
  final app = MaterialApp.router(
    routerConfig: router,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
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
      localCacheProvider.overrideWithValue(
        FakeLocalCache()..writeString('guest_cart_id', 'guest-1'),
      ),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'customer-token' : null),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      if (storeCredit != null)
        storeCreditRepositoryProvider.overrideWithValue(storeCredit),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      publicGraphqlClientProvider.overrideWithValue(
        publicClient ?? fakeHubAppClient(publicAnswers),
      ),
      cartRepositoryProvider.overrideWithValue(
        cartRepository ?? FakeCartRepository(),
      ),
      catalogRepositoryProvider.overrideWithValue(
        catalogRepository ?? FakeCatalogRepository(),
      ),
      freeShippingThresholdProvider.overrideWith((ref) async => null),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Riyadh'),
      storeFeaturesProvider.overrideWith((ref) async => StoreFeatures.none),
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// Sizes the test view like a phone, [height] tall.
void phoneView(WidgetTester tester, {double height = 844}) {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
