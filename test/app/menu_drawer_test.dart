import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/shell/menu_drawer.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../support/fakes.dart';
import '../support/hubapp_fakes.dart';

/// Every route the drawer can open, as a stub that names itself.
const List<String> _destinations = [
  AppRoutes.home,
  AppRoutes.account,
  AppRoutes.signIn,
  AppRoutes.orders,
  AppRoutes.guestTrackOrder,
  AppRoutes.wishlist,
  AppRoutes.addresses,
  AppRoutes.notifications,
  AppRoutes.help,
  AppRoutes.deals,
  AppRoutes.bundles,
  AppRoutes.brands,
  AppRoutes.stores,
];

Future<void> _pump(
  WidgetTester tester, {
  String? token,
  HubAppState hubApp = const HubAppState.unavailable(),
  FakeLocalCache? cache,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/menu',
    routes: [
      GoRoute(
        path: '/menu',
        builder: (_, __) => const Scaffold(body: MenuDrawer()),
      ),
      for (final path in _destinations)
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('route $path')),
        ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(cache ?? FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        storeRepositoryProvider.overrideWithValue(
          FakeStoreRepository(kSampleStores),
        ),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
        customerOrderCountProvider.overrideWith((ref) => 3),
        hubAppOverride(hubApp),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('a customer sees orders and wishlist counts, no vouchers', (
    tester,
  ) async {
    await _pump(tester, token: 'persisted');
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // orders
    expect(find.text(en.navWishlist), findsOneWidget);
    // Nothing in Magento counts vouchers: no invented "0 Vouchers" tile.
    expect(find.text('Vouchers'), findsNothing);
  });

  testWidgets('Build 2 lists deals, bundles, brands and stores', (
    tester,
  ) async {
    await _pump(tester, hubApp: const HubAppState.available(kSampleHmAppConfig));
    for (final label in [
      en.homeTodaysDeals,
      en.bundlesTitle,
      en.brandsScreenTitle,
      en.storesTitle,
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    await tester.tap(find.text(en.storesTitle));
    await tester.pumpAndSettle();
    expect(find.text('route ${AppRoutes.stores}'), findsOneWidget);
  });

  testWidgets('Build 1 has none of the Hub Market App lists', (tester) async {
    await _pump(tester);
    for (final label in [
      en.homeTodaysDeals,
      en.bundlesTitle,
      en.brandsScreenTitle,
      en.storesTitle,
    ]) {
      expect(find.text(label), findsNothing, reason: label);
    }
  });
}
