import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/presentation/account_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

const _testContact = StoreContact(
  company: 'Hub Market',
  address: 'Dubai, UAE',
  phone: '+971500000000',
  phoneDisplay: '+971 50 000 0000',
  email: 'info@hub-market.magento2.click',
  hours: '',
  whatsapp: 'https://wa.me/971500000000',
  website: 'https://hub-market.magento2.click',
);

Widget _harness({
  String? token,
  String locale = 'en',
  bool push = false,
  bool newsletter = true,
}) {
  final router = GoRouter(
    initialLocation: '/account',
    routes: [
      GoRoute(path: '/account', builder: (_, __) => const AccountScreen()),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/signin',
        '/signup',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      storeContactProvider.overrideWithValue(_testContact),
      // Keep the authenticated view's quick-stats / nav counts offline so no
      // real GraphQL query schedules a retry-backoff timer.
      customerOrderCountProvider.overrideWith((ref) => 0),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      pushNotificationsAvailableProvider.overrideWithValue(push),
      storeFeaturesProvider.overrideWith(
        (ref) async => StoreFeatures(newsletterEnabled: newsletter),
      ),
      // Build 1: no Hub Market App, so no My credit row and no My returns
      // (see the store credit and returns tests).
      hubAppOverride(const HubAppState.unavailable()),
    ],
    child: MaterialApp.router(
      routerConfig: router,
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

void main() {
  testWidgets('guest sees sign-in / create-account prompts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(token: null));
    await tester.pumpAndSettle();

    expect(find.text('Your Hub Market account'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Create Account'), findsWidgets);
  });

  testWidgets('authenticated session shows the customer and sign-out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pumpAndSettle();

    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('layla@example.com'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);
  });

  testWidgets('links reviews, newsletter, privacy, help and about', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pumpAndSettle();

    expect(find.text('My product reviews'), findsOneWidget);
    expect(find.text('Newsletter'), findsOneWidget);
    // Push has no Firebase behind it yet: no Notifications row.
    expect(find.text('Notifications'), findsNothing);
    // Deletion stays findable by its name on the Account screen.
    expect(find.text('Privacy & data'), findsOneWidget);
    expect(find.text('Delete account'), findsOneWidget);
    expect(find.text('Help centre'), findsOneWidget);
    expect(find.text('About Hub Market'), findsOneWidget);
  });

  testWidgets('rows follow the store switches and FCM', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(token: 'persisted', push: true, newsletter: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Newsletter'), findsNothing);
  });

  testWidgets('renders translated + RTL in Arabic', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(token: 'persisted', locale: 'ar'));
    await tester.pumpAndSettle();

    expect(find.text('طلباتي'), findsOneWidget); // My Orders entry
    expect(find.text('تسجيل الخروج'), findsOneWidget); // Log Out
    expect(
      Directionality.of(tester.element(find.text('طلباتي'))),
      TextDirection.rtl,
    );
  });
}
