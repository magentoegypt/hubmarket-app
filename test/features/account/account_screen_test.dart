import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/account/presentation/account_overview.dart';
import 'package:hubmarket_app/features/account/presentation/account_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
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
  FakeLocalCache? cache,
  List<SavedCard> cards = const [],
  AccountOrdersOverview? overview,
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
      for (final p in [
        AppRoutes.orders,
        AppRoutes.guestTrackOrder,
        AppRoutes.settings,
        AppRoutes.help,
      ])
        GoRoute(
          path: p,
          builder: (_, __) => Scaffold(body: Text('route $p')),
        ),
    ],
  );
  return ProviderScope(
    overrides: [
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      localCacheProvider.overrideWithValue(cache ?? FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      storeContactProvider.overrideWithValue(_testContact),
      // Keep the authenticated view's quick-stats / nav counts offline so no
      // real GraphQL query schedules a retry-backoff timer.
      customerOrderCountProvider.overrideWith((ref) => 0),
      // ... and what the tiles and the stats card count: no order history,
      // no saved address.
      accountOrdersOverviewProvider.overrideWith((ref) async => overview),
      addressesProvider.overrideWith((ref) async => const []),
      savedCardsProvider.overrideWith((ref) async => cards),
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

/// A device that placed guest order 2000000037 (see `GuestOrderStore`).
FakeLocalCache _cacheWithGuestOrder() => FakeLocalCache()
  ..writeString(
    'guest_orders',
    jsonEncode([
      {'number': '2000000037', 'token': 'order-token'},
    ]),
  );

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

  // Neither needs an account: a guest has no other way to the language switch
  // (Welcome shows once per launch) or to the Help centre.
  group('a guest has the language and the Help centre', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));

    testWidgets('Language shows the language and opens Settings', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(token: null));
      await tester.pumpAndSettle();
      expect(find.text(en.accountGroupPreferences.toUpperCase()), findsOneWidget);
      expect(find.text(en.languageToggleLabel), findsOneWidget);
      expect(find.text(en.languageEnglish), findsOneWidget);

      await tester.tap(find.text(en.languageToggleLabel));
      await tester.pumpAndSettle();
      expect(find.text('route ${AppRoutes.settings}'), findsOneWidget);
    });

    testWidgets('Help centre opens the Help screen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(token: null));
      await tester.pumpAndSettle();
      expect(find.text(en.accountGroupHelp.toUpperCase()), findsOneWidget);

      await tester.tap(find.text(en.helpCentreTitle));
      await tester.pumpAndSettle();
      expect(find.text('route ${AppRoutes.help}'), findsOneWidget);
    });

    testWidgets('in Arabic the page reads right to left with Arabic as the '
        'language', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(token: null, locale: 'ar'));
      await tester.pumpAndSettle();
      expect(find.text(ar.languageToggleLabel), findsOneWidget);
      expect(find.text(ar.languageArabic), findsOneWidget);
      expect(find.text(ar.helpCentreTitle), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(ar.helpCentreTitle))),
        TextDirection.rtl,
      );
    });

    // The WhatsApp and Sell rows belong to a signed-in customer's Help group;
    // the Help centre itself lists the contact channels.
    testWidgets('no WhatsApp or Sell row for a guest', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(token: null));
      await tester.pumpAndSettle();
      expect(find.text(en.accountContactWhatsApp), findsNothing);
      expect(find.text(en.accountSellOnHubMarket), findsNothing);
    });

    testWidgets('signed in keeps the same Language row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(token: 'persisted'));
      await tester.pumpAndSettle();
      expect(find.text(en.languageToggleLabel), findsOneWidget);
      expect(find.text(en.languageEnglish), findsOneWidget);

      await tester.tap(find.text(en.languageToggleLabel));
      await tester.pumpAndSettle();
      expect(find.text('route ${AppRoutes.settings}'), findsOneWidget);
    });
  });

  group('a guest gets back to their orders', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));

    testWidgets('Track an order opens the lookup', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_harness(token: null));
      await tester.pumpAndSettle();
      // Nothing remembered on this device yet: no empty My Orders.
      expect(find.text(en.accountOrders), findsNothing);

      await tester.tap(find.text(en.accountTrackOrder));
      await tester.pumpAndSettle();
      expect(find.text('route ${AppRoutes.guestTrackOrder}'), findsOneWidget);
    });

    testWidgets('My Orders lists the orders this device remembers', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _harness(token: null, cache: _cacheWithGuestOrder()),
      );
      await tester.pumpAndSettle();
      expect(find.text(en.accountTrackOrder), findsOneWidget);

      await tester.tap(find.text(en.accountOrders));
      await tester.pumpAndSettle();
      expect(find.text('route ${AppRoutes.orders}'), findsOneWidget);
    });

    test('the FAQ sends guests to these rows', () {
      for (final l10n in [en, ar]) {
        expect(l10n.helpA7, contains(l10n.accountTrackOrder));
        expect(
          l10n.helpA7.toLowerCase(),
          contains(l10n.accountOrders.toLowerCase()),
        );
      }
    });
  });

  testWidgets('authenticated session shows the customer and sign-out', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pumpAndSettle();

    // The header (Figma 20): the name over what the customer has, and Edit
    // profile; Sign out ends the page.
    expect(find.text('Layla Hassan'), findsOneWidget);
    expect(find.text('0 orders · 0 wishlist items'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('quick tiles: orders, wishlist, addresses — no returns, no '
      'vouchers', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pumpAndSettle();

    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Wishlist'), findsWidgets); // the tile and the tab bar
    expect(find.text('Addresses'), findsOneWidget);
    expect(find.text('0 items'), findsOneWidget); // the wishlist's count
    expect(find.text('0 saved'), findsOneWidget); // saved addresses
    // Build 1 takes no returns in the app, and nothing in Magento counts
    // vouchers: no Returns tile, no invented "0 Vouchers".
    expect(find.text('Returns'), findsNothing);
    expect(find.text('Vouchers'), findsNothing);
  });

  testWidgets('the tiles count what the history holds, and the stats card '
      'adds it up', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(
        token: 'persisted',
        overview: const AccountOrdersOverview(
          activeCount: 2,
          stats: ShoppingStats(
            totalSpent: Money(amount: 1284, currency: 'AED'),
            ordersThisYear: 7,
            averageOrder: Money(amount: 183.4, currency: 'AED'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 active'), findsOneWidget);
    expect(find.text('Shopping stats'), findsOneWidget);
    // Whole dirhams, as the frame prints them.
    expect(find.text('AED 1,284'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('AED 183'), findsOneWidget);
    expect(find.text('Total spent'), findsOneWidget);
    expect(find.text('Orders this year'), findsOneWidget);
    expect(find.text('Avg. order'), findsOneWidget);
  });

  testWidgets('no stats card without the order history', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The overview is null (offline, or too many orders to add up): no card,
    // and the Orders tile has nothing to count.
    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pumpAndSettle();
    expect(find.text('Shopping stats'), findsNothing);
    expect(find.textContaining('active'), findsNothing);
  });

  testWidgets('no Stored payment methods row with no saved card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // No card gateway in the app, so nothing to list: no row.
    await tester.pumpWidget(_harness(token: 'persisted'));
    await tester.pumpAndSettle();
    expect(find.text('Stored payment methods'), findsNothing);
  });

  testWidgets('Stored payment methods once the vault holds a card', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(
        token: 'persisted',
        cards: const [
          SavedCard(publicHash: 'h1', brandCode: 'VI', last4: '1111'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stored payment methods'), findsOneWidget);
  });

  testWidgets('links reviews, newsletter, privacy, help and WhatsApp', (
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
    // The store publishes a WhatsApp number (see _testContact).
    expect(find.text('Contact Hub Market (WhatsApp)'), findsOneWidget);
    // About moved to the Help centre's About & legal group (Figma 27).
    expect(find.text('About Hub Market'), findsNothing);
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
