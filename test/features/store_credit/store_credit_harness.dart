import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/store_credit_fakes.dart';

/// The HubApp probe as a test wants it: the module deployed with store
/// credit on, deployed with it off, or not there at all.
Override creditHubApp({bool deployed = true, bool creditOn = true}) =>
    accountHubApp(deployed: deployed, storeCredit: creditOn);

/// A screen on a router with stand-ins for the routes it can leave to, over
/// fakes: a signed-in customer (unless [signedIn] is false), [credit] as the
/// store-credit backend, [cart] as the cart backend and [hubApp] as the probe.
Widget storeCreditHarness({
  required Widget screen,
  required FakeStoreCreditRepository credit,
  FakeCartRepository? cart,
  String locale = 'en',
  bool signedIn = true,
  Override? hubApp,
  GlobalKey? boundary,
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final path in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.signIn,
        AppRoutes.signUp,
        AppRoutes.myCredit,
        AppRoutes.orders,
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text('route $path')),
        ),
      // One order by its number (`AppRoutes.orderByNumber`).
      GoRoute(
        path: '${AppRoutes.orders}/:number',
        builder: (_, state) =>
            Scaffold(body: Text('order ${state.pathParameters['number']}')),
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
      hubApp ?? creditHubApp(),
      storeCreditRepositoryProvider.overrideWithValue(credit),
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'persisted' : null),
      ),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(cart ?? FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
      customerOrderCountProvider.overrideWith((ref) => 7),
      storeFeaturesProvider.overrideWith(
        (ref) async => const StoreFeatures(newsletterEnabled: true),
      ),
      storeContactProvider.overrideWithValue(
        const StoreContact(website: 'https://hub-market.magento2.click'),
      ),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
      pushNotificationsAvailableProvider.overrideWithValue(false),
      ...overrides,
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}
