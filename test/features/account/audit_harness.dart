import 'dart:async' show unawaited;

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
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/domain/customer.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/store_credit_fakes.dart';

/// The customer of the Account frames (Figma 20, 20c, 27).
const Customer kAuditCustomer = Customer(
  firstName: 'Sara',
  lastName: 'Ahmed',
  email: 'sara.ahmed@gmail.com',
  mobileNumber: '+971501234567',
);

/// The Arabic frames' customer.
const Customer kAuditCustomerAr = Customer(
  firstName: 'سارة',
  lastName: 'أحمد',
  email: 'sara.ahmed@gmail.com',
  mobileNumber: '+971501234567',
);

/// HubApp there with returns and store credit on, as the Account frame
/// (20) assumes.
const HubAppState kAuditHubApp = HubAppState.available(
  HmAppConfig(
    storeCode: 'en',
    locale: 'en_US',
    features: {'returns': true, 'store_credit': true},
  ),
);

/// A wishlist holding [count] products.
Future<FakeWishlistRepository> wishlistOf(int count) async {
  final repository = FakeWishlistRepository();
  for (var i = 1; i <= count; i++) {
    await repository.addProduct('wl-1', 'sku-$i');
  }
  return repository;
}

/// Mounts [screen] the way the app reaches it: pushed over an Account stub
/// (so the app bar has its back arrow), 390 wide at [height], in [locale],
/// over fakes for everything the Account screens read. [overrides] go last, so
/// they win. Returns the boundary key for `captureScreen`.
Future<GlobalKey> pumpAuditScreen(
  WidgetTester tester, {
  required Widget screen,
  String locale = 'en',
  double height = 844,
  bool signedIn = true,
  bool pushed = true,
  Customer? customer,
  HubAppState hubApp = kAuditHubApp,
  FakeWishlistRepository? wishlist,
  FakeStoreCreditRepository? credit,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  final router = GoRouter(
    initialLocation: pushed ? AppRoutes.home : '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.signIn,
        AppRoutes.signUp,
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hubAppOverride(hubApp),
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(
          FakeSecureTokenStore(signedIn ? 'persisted' : null),
        ),
        storeRepositoryProvider.overrideWithValue(
          FakeStoreRepository(kSampleStores),
        ),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            customer:
                customer ??
                (locale == 'ar' ? kAuditCustomerAr : kAuditCustomer),
          ),
        ),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        wishlistRepositoryProvider.overrideWithValue(
          wishlist ?? FakeWishlistRepository(),
        ),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
        cmsRepositoryProvider.overrideWithValue(FakeCmsRepository()),
        storeCreditRepositoryProvider.overrideWithValue(
          credit ?? FakeStoreCreditRepository(),
        ),
        savedCardsProvider.overrideWith((ref) async => const <SavedCard>[]),
        customerOrderCountProvider.overrideWith((ref) => 7),
        storeFeaturesProvider.overrideWith(
          (ref) async => const StoreFeatures(
            newsletterEnabled: true,
            contactEnabled: true,
          ),
        ),
        storeContactProvider.overrideWithValue(
          const StoreContact(
            website: 'https://hub-market.magento2.click',
            whatsapp: 'https://wa.me/13156360140',
          ),
        ),
        storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
        pushNotificationsAvailableProvider.overrideWithValue(true),
        ...overrides,
      ],
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp.router(
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
        ),
      ),
    ),
  );
  // The store views, as the app's bootstrap loads them: store URLs need them.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  await tester.runAsync(
    () => container.read(storeControllerProvider.notifier).loadStores(),
  );
  await tester.pumpAndSettle();
  if (pushed) {
    unawaited(router.push('/screen'));
    await tester.pumpAndSettle();
  }
  return boundary;
}

/// `captureScreen` under the name `pairs.py` looks for: `<name>_<locale>`.
Future<void> captureAudit(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
  String locale,
) async {
  expect(tester.takeException(), isNull);
  await captureScreen(tester, boundary, '${name}_$locale');
}

