import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/home/data/home_content_repository.dart';
import 'package:hubmarket_app/features/home/presentation/active_order_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/home_active_order.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';
import 'package:intl/intl.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import 'hm_home_fixtures.dart';

String _stamp(DateTime time) => DateFormat('yyyy-MM-dd HH:mm:ss').format(time);

/// An order placed at noon [daysAgo] days before [now] (today), with [lines]
/// lines. Noon, so reading it in the store's zone keeps its day.
CustomerOrder _order(
  String number,
  String status, {
  int daysAgo = 1,
  int lines = 2,
  DateTime? now,
}) => CustomerOrder(
  number: number,
  status: status,
  date: _stamp(
    DateUtils.dateOnly(
      now ?? DateTime.now(),
    ).add(const Duration(hours: 12)).subtract(Duration(days: daysAgo)),
  ),
  id: 'id-$number',
  total: const Money(amount: 553, currency: 'AED'),
  lines: [
    for (var i = 0; i < lines; i++)
      OrderLine(name: 'Line $i', quantity: 1),
  ],
);

/// The recent-orders lookup failing, as a dropped connection would.
class _FailingAccount extends FakeAccountRepository {
  @override
  Future<List<CustomerOrder>> fetchRecentOrders({int pageSize = 3}) async {
    recentOrderCalls++;
    throw const Failure(FailureKind.network);
  }
}

const _cms = <String, String>{
  HomeCmsBlocks.deliveryPromise:
      '<p>Free delivery on qualifying orders &middot; Fast nationwide shipping</p>',
  HomeCmsBlocks.trust: kTrustHtml,
};

const _categories = <Category>[
  Category(
    uid: 'NQ==',
    name: 'Sports & Fitness',
    urlKey: 'sports',
    productCount: 7,
  ),
];

/// A rail of v3 cards: two rated products (live Luma sample data) and one
/// without reviews.
const _rail = <Product>[
  Product(
    sku: '24-WG080',
    name: 'Sprite Yoga Companion Kit',
    urlKey: 'sprite-yoga-companion-kit',
    regularPrice: Money(amount: 77, currency: 'AED'),
    finalPrice: Money(amount: 61, currency: 'AED'),
    typeId: 'bundle',
    ratingSummary: 94,
    reviewCount: 3,
  ),
  Product(
    sku: '24-UG04',
    name: 'Zing Jump Rope',
    urlKey: 'zing-jump-rope',
    regularPrice: Money(amount: 12, currency: 'AED'),
    finalPrice: Money(amount: 12, currency: 'AED'),
    ratingSummary: 93,
    reviewCount: 1,
  ),
  Product(
    sku: 'sofa',
    name: 'Corner Sofa Bed',
    urlKey: 'corner-sofa-bed',
    regularPrice: Money(amount: 500, currency: 'AED'),
    finalPrice: Money(amount: 425, currency: 'AED'),
  ),
];

Widget _app({
  required String locale,
  required FakeAccountRepository account,
  GlobalKey? boundary,
  bool signedIn = true,
  HubAppState hubApp = const HubAppState.unavailable(),
}) {
  Widget stub(BuildContext context, GoRouterState state) {
    final extra = state.extra;
    return Scaffold(
      appBar: AppBar(),
      body: Text(
        extra is CustomerOrder
            ? '${state.uri.path} ${extra.number}'
            : 'route ${state.uri}',
      ),
    );
  }

  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HubHomeScreen()),
      for (final p in [
        AppRoutes.orderDetail,
        AppRoutes.orderTracking,
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
        '/search',
        '/notifications',
        '/addresses',
        '/deals',
        '/bundles',
        '/brands',
        '/stores',
        '/orders',
        '/track-order',
        '/page',
        '/category/:uid',
        '/product/:urlKey',
        '/brand/:urlKey',
        '/store/:code',
      ])
        GoRoute(path: p, builder: stub),
    ],
  );
  final countdown = DateTime.now().add(const Duration(days: 2, hours: 14));
  final app = MaterialApp.router(
    debugShowCheckedModeBanner: false,
    routerConfig: router,
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
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'persisted' : null),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(account),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      hubAppOverride(hubApp),
      hmHomeProvider.overrideWith(
        (ref) async => hubApp.isAvailable
            ? hmHomeFromJson(
                hmHomeJson(countdown: countdown, arabic: locale == 'ar'),
              )
            : null,
      ),
      homeCmsBlocksProvider.overrideWith((ref) async => _cms),
      homeCategoriesProvider.overrideWith((ref) async => _categories),
      categoryThumbnailsProvider.overrideWith(
        (ref, key) async => const <String, String>{},
      ),
      homeCategoryRailProvider.overrideWith((ref, uid) async => _rail),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget app, {
  Size size = const Size(390, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// The card's details line for [order]: number, day and items.
String _details(CustomerOrder order, String locale) {
  final l10n = lookupAppLocalizations(Locale(locale));
  final day = DateFormat('d MMM', locale).format(DateTime.parse(order.date));
  return '#${order.number} · $day · ${l10n.orderItemCount(order.itemCount)}';
}

void main() {
  setUpAll(loadAppFonts);

  group('pickActiveOrder', () {
    final now = DateTime(2026, 9, 30, 12);

    test('the newest order that is neither complete nor cancelled', () {
      final orders = [
        _order('000000250', 'Complete', daysAgo: 1, now: now),
        _order('000000249', 'Canceled', daysAgo: 2, now: now),
        _order('000000248', 'Processing', daysAgo: 3, now: now),
        _order('000000247', 'Pending', daysAgo: 4, now: now),
      ];
      expect(pickActiveOrder(orders, now: now)?.number, '000000248');
    });

    test('delivered, closed and refunded orders are not active', () {
      final orders = [
        _order('1', 'Delivered', now: now),
        _order('2', 'Closed', now: now),
        _order('3', 'Refunded', now: now),
      ];
      expect(pickActiveOrder(orders, now: now), isNull);
    });

    test('an open order older than the window is not recent', () {
      final orders = [_order('000000100', 'Pending', daysAgo: 45, now: now)];
      expect(pickActiveOrder(orders, now: now), isNull);
      expect(
        pickActiveOrder([_order('000000101', 'Pending', daysAgo: 29, now: now)],
            now: now)?.number,
        '000000101',
      );
    });

    test('no orders => null', () {
      expect(pickActiveOrder(const [], now: now), isNull);
    });
  });

  group('activeOrderProvider', () {
    Future<ProviderContainer> container(
      FakeAccountRepository account, {
      bool signedIn = true,
    }) async {
      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
          secureTokenStoreProvider.overrideWithValue(
            FakeSecureTokenStore(signedIn ? 'persisted' : null),
          ),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
          accountRepositoryProvider.overrideWithValue(account),
        ],
      );
      addTearDown(container.dispose);
      container.read(authControllerProvider);
      for (var i = 0; i < 50; i++) {
        if (container.read(authControllerProvider).status !=
            AuthStatus.unknown) {
          break;
        }
        await Future<void>.delayed(Duration.zero);
      }
      return container;
    }

    test('a guest never asks', () async {
      final account = FakeAccountRepository(
        orders: [_order('000000248', 'Processing')],
      );
      final c = await container(account, signedIn: false);
      expect(await c.read(activeOrderProvider.future), isNull);
      expect(account.recentOrderCalls, 0);
    });

    test('one query, kept for the session; refreshing asks again', () async {
      final account = FakeAccountRepository(
        orders: [
          _order('000000250', 'Complete'),
          _order('000000248', 'Processing'),
        ],
      );
      final c = await container(account);
      final sub = c.listen(activeOrderProvider, (_, __) {});
      addTearDown(sub.close);
      expect((await c.read(activeOrderProvider.future))?.number, '000000248');
      expect(await c.read(activeOrderProvider.future), isNotNull);
      expect(account.recentOrderCalls, 1);

      c.invalidate(activeOrderProvider);
      await c.read(activeOrderProvider.future);
      expect(account.recentOrderCalls, 2);
    });

    test('a failed lookup hides the card instead of failing', () async {
      final account = _FailingAccount();
      final c = await container(account);
      expect(await c.read(activeOrderProvider.future), isNull);
      expect(account.recentOrderCalls, 1);
    });
  });

  group('Home card (Figma 07 "Active order")', () {
    tearDown(() => NotificationInbox.instance.items.value = const []);

    for (final locale in const ['en', 'ar']) {
      testWidgets('Build 1: under the delivery strip, with the bell dot '
          '($locale)', (tester) async {
        NotificationInbox.instance.items.value = [
          NotificationItem(
            id: 'n1',
            kind: NotificationKind.order,
            title: 'Your order shipped',
            body: '',
            receivedAt: DateTime.now(),
          ),
        ];
        final order = _order('000000248', 'Processing');
        final key = GlobalKey();
        await _pump(
          tester,
          _app(
            locale: locale,
            boundary: key,
            account: FakeAccountRepository(
              orders: [_order('000000250', 'Complete'), order],
            ),
          ),
        );
        await captureScreen(tester, key, 'home_active_order_$locale');

        final card = find.byType(ActiveOrderCard);
        expect(card, findsOneWidget);
        expect(find.text('Processing'), findsOneWidget);
        expect(find.text(_details(order, locale)), findsOneWidget);
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(
          find.descendant(of: card, matching: find.text(l10n.orderTrack)),
          findsOneWidget,
        );
        // Below the promise strip, above Shop by category.
        final strip = tester.getTopLeft(find.textContaining('Free delivery'));
        expect(tester.getTopLeft(card).dy, greaterThan(strip.dy));
        expect(
          tester.getTopLeft(card).dy,
          lessThan(tester.getTopLeft(find.text(l10n.homeShopByCategory)).dy),
        );
        // The bell's unread dot.
        expect(
          find.byWidgetPredicate((w) => w is Badge && w.isLabelVisible),
          findsOneWidget,
        );
        // The v3 card's rating.
        expect(find.text('4.7'), findsNWidgets(2));
        expect(find.text('(3)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Build 2: below the admin\'s delivery strip ($locale)', (
        tester,
      ) async {
        final order = _order('000000248', 'Pending', lines: 1);
        final key = GlobalKey();
        await _pump(
          tester,
          _app(
            locale: locale,
            boundary: key,
            hubApp: const HubAppState.available(kSampleHmAppConfig),
            account: FakeAccountRepository(orders: [order]),
          ),
        );
        await captureScreen(tester, key, 'home_hubapp_active_order_$locale');

        final card = find.byType(ActiveOrderCard);
        expect(card, findsOneWidget);
        expect(find.text(_details(order, locale)), findsOneWidget);
        final strip = find.text(
          locale == 'ar'
              ? 'توصيل مجاني للطلبات المؤهلة'
              : 'Free delivery on qualifying orders',
        );
        final hero = find.text(
          locale == 'ar'
              ? 'بقالة طازجة من بائعين محليين'
              : 'Fresh Groceries From Local Vendors',
        );
        expect(
          tester.getTopLeft(card).dy,
          greaterThan(tester.getTopLeft(strip).dy),
        );
        expect(tester.getTopLeft(card).dy, lessThan(tester.getTopLeft(hero).dy));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('tapping the card opens the order; Track opens tracking', (
      tester,
    ) async {
      await _pump(
        tester,
        _app(
          locale: 'en',
          account: FakeAccountRepository(
            orders: [_order('000000248', 'Processing')],
          ),
        ),
      );
      await tester.tap(find.text('Processing'));
      await tester.pumpAndSettle();
      expect(find.text('${AppRoutes.orderDetail} 000000248'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();
      expect(find.text('${AppRoutes.orderTracking} 000000248'), findsOneWidget);
    });

    testWidgets('pull-to-refresh asks for the orders again', (tester) async {
      final account = FakeAccountRepository(
        orders: [_order('000000248', 'Processing')],
      );
      await _pump(tester, _app(locale: 'en', account: account));
      expect(account.recentOrderCalls, 1);

      await tester.fling(
        find.byType(ActiveOrderCard),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(account.recentOrderCalls, 2);
      expect(find.byType(ActiveOrderCard), findsOneWidget);
    });

    testWidgets('hidden for a guest', (tester) async {
      final account = FakeAccountRepository(
        orders: [_order('000000248', 'Processing')],
      );
      await _pump(
        tester,
        _app(locale: 'en', account: account, signedIn: false),
      );
      expect(find.byType(ActiveOrderCard), findsNothing);
      expect(account.recentOrderCalls, 0);
      // No unread notifications, no dot.
      expect(
        find.byWidgetPredicate((w) => w is Badge && w.isLabelVisible),
        findsNothing,
      );
    });

    testWidgets('hidden when every recent order is complete or cancelled', (
      tester,
    ) async {
      await _pump(
        tester,
        _app(
          locale: 'en',
          account: FakeAccountRepository(
            orders: [
              _order('000000250', 'Complete'),
              _order('000000249', 'Canceled'),
            ],
          ),
        ),
      );
      expect(find.byType(ActiveOrderCard), findsNothing);
      expect(find.text('Shop by category'), findsOneWidget);
    });
  });
}
