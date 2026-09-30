import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

/// AED 100 in the cart: AED 50 short of free delivery at 150.
class FilledCart extends FakeCartRepository {
  @override
  Future<Cart> getCart(String cartId) async => const Cart(
    id: 'guest-1',
    totalQuantity: 1,
    items: [
      CartItem(
        uid: 'line-1',
        sku: 'SOFA',
        name: 'Corner Sofa Bed',
        quantity: 1,
        unitPrice: Money(amount: 100, currency: 'AED'),
        rowTotal: Money(amount: 100, currency: 'AED'),
      ),
    ],
    totals: CartTotals(
      subtotal: Money(amount: 100, currency: 'AED'),
      grandTotal: Money(amount: 100, currency: 'AED'),
    ),
  );
}

/// The cart tab for a guest with a cart on this device (so it loads it from
/// [cart]), Build 1, free delivery from [freeShipping] when set.
Widget cartScreenApp({
  required String locale,
  required CartRepository cart,
  bool dark = false,
  double? freeShipping,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.cart,
    routes: [
      GoRoute(path: AppRoutes.cart, builder: (_, __) => const CartScreen()),
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
    theme: dark ? AppTheme.dark(locale) : AppTheme.light(locale),
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
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.unavailable()),
      cartRepositoryProvider.overrideWithValue(cart),
      freeShippingThresholdProvider.overrideWith((ref) async => freeShipping),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// A 390 × 844 phone.
void phoneView(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
