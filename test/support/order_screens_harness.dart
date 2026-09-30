import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/util/launch.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_tracking_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import 'fakes.dart';
import 'hubapp_fakes.dart';

/// The order screens — 22 order detail, 26 Track order — over one [order],
/// with HubApp available and every route they may leave to.
///
/// "Track parcel" opens nothing: the URIs it asks for land in [opened], and
/// the launcher answers [opens].
Widget orderScreensApp(
  CustomerOrder order, {
  String screen = AppRoutes.orderDetail,
  String locale = 'en',
  List<Uri>? opened,
  bool opens = true,
  ThemeMode themeMode = ThemeMode.light,
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: screen,
    routes: [
      GoRoute(
        path: AppRoutes.orderDetail,
        builder: (_, __) => OrderDetailScreen(order: order),
      ),
      GoRoute(
        path: AppRoutes.orderTracking,
        builder: (_, __) => OrderTrackingScreen(order: order),
      ),
      for (final path in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.help,
      ])
        GoRoute(
          path: path,
          builder: (_, __) => Scaffold(body: Text(path)),
        ),
      GoRoute(
        path: '/store/:code',
        builder: (_, state) =>
            Scaffold(body: Text('store ${state.pathParameters['code']}')),
      ),
    ],
  );
  final app = MaterialApp.router(
    routerConfig: router,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(locale),
    darkTheme: AppTheme.dark(locale),
    themeMode: themeMode,
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
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Riyadh'),
      storeFeaturesProvider.overrideWith((ref) async => StoreFeatures.none),
      externalUriLauncherProvider.overrideWithValue((uri) async {
        opened?.add(uri);
        return opens;
      }),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}
