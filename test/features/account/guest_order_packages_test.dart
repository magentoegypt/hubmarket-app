import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/guest_track_order_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../marketplace/marketplace_harness.dart' show twoStoreOrder;

/// Answers the Track order form with [order].
class _GuestRepo implements AccountRepository {
  _GuestRepo(this.order);

  final CustomerOrder order;

  @override
  Future<CustomerOrder> fetchGuestOrder({
    required String number,
    required String email,
    required String lastname,
  }) async => order;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Track order (26): the form, the order it finds, and View order details,
/// which opens that order's page (22).
Future<void> _lookUp(WidgetTester tester, CustomerOrder order) async {
  // Wide, as the other Track order tests: the test font's square glyphs
  // overflow "Need help?" at phone width.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.guestTrackOrder,
    routes: [
      GoRoute(
        path: AppRoutes.guestTrackOrder,
        builder: (_, __) => const GuestTrackOrderScreen(),
      ),
      GoRoute(
        path: AppRoutes.orderDetail,
        builder: (_, state) =>
            OrderDetailScreen(order: state.extra! as CustomerOrder),
      ),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        accountRepositoryProvider.overrideWithValue(_GuestRepo(order)),
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
        catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
        storeTimezoneProvider.overrideWith((ref) async => 'Asia/Riyadh'),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
        hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), order.number);
  await tester.enterText(fields.at(1), 'Ahmed');
  await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
  await tester.tap(find.text('Find order'));
  await tester.pumpAndSettle();
  // The order shows under the form; its page opens from View order details.
  expect(find.byType(OrderDetailScreen), findsNothing);
  await tester.tap(find.text('View order details'));
  await tester.pumpAndSettle();
  expect(find.byType(OrderDetailScreen), findsOneWidget);
}

void main() {
  testWidgets('a guest order found with HubApp comes one package per store', (
    tester,
  ) async {
    await _lookUp(tester, twoStoreOrder());

    expect(find.text('Package 1 · loly store'), findsOneWidget);
    expect(find.text('Package 2 · MIA CO'), findsOneWidget);
    expect(find.text('Corner Sofa Bed'), findsOneWidget);
    expect(find.text('Dining Chair with Gold Metal Legs'), findsOneWidget);
  });

  testWidgets('without sellers the items stay one list, as today', (
    tester,
  ) async {
    await _lookUp(tester, twoStoreOrder(withSellers: false));

    expect(find.textContaining('Package'), findsNothing);
    expect(find.text('Corner Sofa Bed'), findsOneWidget);
  });

  test('the guest lookup asks for each line seller with HubApp', () async {
    final server = RecordingGraphQLClient(
      (_, __) => {
        'guestOrder': {
          '__typename': 'CustomerOrder',
          'number': '000000248',
          'status': 'Processing',
          'order_date': '2026-09-28 10:42:00',
          'items': [
            {
              '__typename': 'OrderItem',
              'product_name': 'Corner Sofa Bed',
              'quantity_ordered': 1,
              'hm_seller': sellerJson('mia', 'MIA CO'),
            },
          ],
        },
      },
    );
    final order = await AccountRepository(
      server.client,
      marketplace: RecordingMarketplaceGate(),
    ).fetchGuestOrder(number: '000000248', email: 'a@b.c', lastname: 'Ahmed');

    expect(server.documents.single, contains('hm_seller'));
    expect(order.placedAsGuest, isTrue);
    expect(order.lines.single.seller?.name, 'MIA CO');
  });
}
