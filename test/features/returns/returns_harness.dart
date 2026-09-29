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
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/account_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_topic_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/faq.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/returns/data/returns_repository.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/my_returns_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/request_return_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/return_detail_screen.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/returns_fakes.dart';

/// HubApp there, with the `returns` flag on.
const HubAppState kReturnsOn = HubAppState.available(kSampleHmAppConfig);

/// HubApp there, `returns` flag off.
const HubAppState kReturnsFlagOff = HubAppState.available(
  HmAppConfig(storeCode: 'en', features: {'returns': false}),
);

/// HubApp there, `returns` flag not listed (off by default).
const HubAppState kReturnsFlagUnset = HubAppState.available(
  HmAppConfig(storeCode: 'en'),
);

/// A signed-in customer's order the server lists as returnable
/// ([kTwoSellerOrder]).
const CustomerOrder kReturnableCustomerOrder = CustomerOrder(
  number: '000000150',
  status: 'Complete',
  date: '2026-09-22 12:30:00',
  id: 'MTUw',
  availableActions: {'REORDER'},
  invoiceCount: 1,
  shipmentCount: 1,
  lines: [OrderLine(name: 'Short Square-Neck T-Shirt', quantity: 2)],
);

/// Mounts the app's returns routes (and the screens that lead to them) at
/// [location], with [returns] as the returns backend.
Future<ProviderContainer> pumpReturns(
  WidgetTester tester, {
  required String location,
  Object? extra,
  String locale = 'en',
  HubAppState hubApp = kReturnsOn,
  bool signedIn = true,
  FakeReturnsRepository? returns,
  Size size = const Size(390, 1600),
  GlobalKey? boundary,
  bool dark = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: location,
    initialExtra: extra,
    routes: [
      GoRoute(
        path: AppRoutes.returns,
        builder: (_, __) => const MyReturnsScreen(),
      ),
      GoRoute(
        path: '${AppRoutes.returns}/:id',
        builder: (_, s) =>
            ReturnDetailScreen(returnId: int.parse(s.pathParameters['id']!)),
      ),
      GoRoute(
        path: AppRoutes.returnRequest,
        builder: (_, s) => RequestReturnScreen(
          order: s.extra is ReturnableOrder
              ? s.extra! as ReturnableOrder
              : null,
          orderNumber: s.uri.queryParameters['order'],
        ),
      ),
      GoRoute(
        path: AppRoutes.account,
        builder: (_, __) => const AccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderDetail,
        builder: (_, s) => OrderDetailScreen(order: s.extra! as CustomerOrder),
      ),
      GoRoute(path: AppRoutes.help, builder: (_, __) => const HelpScreen()),
      GoRoute(
        path: AppRoutes.helpTopic,
        builder: (_, s) => HelpTopicScreen(topic: s.extra! as FaqTopic),
      ),
      for (final p in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.signIn,
        AppRoutes.signUp,
        AppRoutes.orders,
        AppRoutes.about,
        AppRoutes.cmsPage,
      ])
        GoRoute(
          path: p,
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
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
      cmsRepositoryProvider.overrideWithValue(
        FakeCmsRepository(blocks: const {'hm_footer_legal': kLegalLinksBlock}),
      ),
      storeFeaturesProvider.overrideWith(
        (ref) async =>
            const StoreFeatures(newsletterEnabled: true, contactEnabled: true),
      ),
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
      returnsRepositoryProvider.overrideWithValue(
        returns ?? FakeReturnsRepository(),
      ),
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
  await tester.pumpAndSettle();
  return container;
}
