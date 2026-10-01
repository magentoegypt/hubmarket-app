import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
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
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/returns/data/returns_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import 'fakes.dart';
import 'hubapp_fakes.dart';
import 'returns_fakes.dart';

/// Mounts one screen of the orders / returns / addresses / wishlist area the
/// way the app does — inside the router, with the app theme, the locale and
/// the usual fakes — for the UI audit captures
/// (`captureScreen(tester, boundary, 'audit_<frame>_<locale>')`, see
/// docs/ui-audit.md). [screen] is mounted at `/screen`; every tab route and
/// the pages a screen leaves to are stubs.
Future<ProviderContainer> pumpAudit(
  WidgetTester tester, {
  required Widget screen,
  String locale = 'en',
  bool signedIn = true,
  double height = 844,
  AccountRepository? account,
  ReturnsRepository? returns,
  WishlistRepository? wishlist,
  StoreFeatures features = const StoreFeatures(
    orderCancellationEnabled: true,
    cancellationReasons: [
      'Changed my mind',
      'Found a better price',
      'Ordered by mistake',
      'Delivery takes too long',
      'Other',
    ],
    newsletterEnabled: true,
    contactEnabled: true,
  ),
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  GlobalKey? boundary,
  List<Override> overrides = const [],
  bool dark = false,
  bool settle = true,

  /// The screen is pushed on top of Home, as every page of the account area
  /// is, so its app bar shows the back button; false mounts it as the root
  /// (a tab).
  bool pushed = true,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: pushed ? AppRoutes.home : '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final path in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.help,
        AppRoutes.signIn,
        AppRoutes.orders,
        AppRoutes.orderDetail,
        AppRoutes.orderTracking,
        AppRoutes.guestTrackOrder,
        AppRoutes.returns,
        AppRoutes.returnRequest,
        AppRoutes.addresses,
        AppRoutes.addressForm,
        '${AppRoutes.returns}/:id',
        '/review/:sku',
        '/product/:urlKey',
        '/store/:code',
      ])
        GoRoute(
          path: path,
          builder: (_, __) => const Scaffold(body: Text('STUB')),
        ),
    ],
  );

  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'persisted' : null),
      ),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(customer: kSampleCustomer),
      ),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      wishlistRepositoryProvider.overrideWithValue(
        wishlist ?? FakeWishlistRepository(),
      ),
      accountRepositoryProvider.overrideWithValue(
        account ?? FakeAccountRepository(),
      ),
      returnsRepositoryProvider.overrideWithValue(
        returns ?? FakeReturnsRepository(),
      ),
      storeFeaturesProvider.overrideWith((ref) async => features),
      storeContactProvider.overrideWithValue(
        const StoreContact(
          website: 'https://hub-market.magento2.click',
          whatsapp: 'https://wa.me/971501234567',
        ),
      ),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
      pushNotificationsAvailableProvider.overrideWithValue(false),
      hubAppOverride(hubApp),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

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
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: boundary == null
          ? app
          : RepaintBoundary(key: boundary, child: app),
    ),
  );
  if (pushed) {
    await tester.pump();
    router.push('/screen');
  }
  if (settle) await tester.pumpAndSettle();
  return container;
}
