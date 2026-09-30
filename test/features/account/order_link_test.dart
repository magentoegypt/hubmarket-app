import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_queries.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/data/guest_order_store.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/guest_track_order_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/orders_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';

const _number = '000000248';

const _order = CustomerOrder(
  number: _number,
  status: 'Processing',
  date: '2026-09-28 10:42:00',
  id: 'MjQ4',
  total: Money(amount: 553, currency: 'AED'),
  lines: [
    OrderLine(
      name: 'Corner Sofa Bed',
      quantity: 1,
      price: Money(amount: 425, currency: 'AED'),
    ),
  ],
);

/// Serves [_order] by its number (to the customer) and by its token (to the
/// guest who placed it), failing the first [failures] number lookups.
class _OrdersRepo implements AccountRepository {
  _OrdersRepo({this.failures = 0});

  int failures;
  final List<String> calls = <String>[];

  @override
  Future<CustomerOrder?> fetchOrderByNumber(String number) async {
    calls.add('number:$number');
    if (failures > 0) {
      failures--;
      throw const Failure(FailureKind.server, detail: 'boom');
    }
    return number == _number ? _order : null;
  }

  @override
  Future<CustomerOrder> fetchGuestOrderByToken(String token) async {
    calls.add('token:$token');
    return _order;
  }

  @override
  Future<OrderPage> fetchOrders({
    int pageSize = 10,
    int currentPage = 1,
  }) async => OrderPage.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The app's own route table at [location], [signedIn] or as a guest whose
/// device remembers [remembered].
Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  required _OrdersRepo repo,
  bool signedIn = true,
  GuestOrderRef? remembered,
}) async {
  final cache = FakeLocalCache();
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'customer-token' : null),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      accountRepositoryProvider.overrideWithValue(repo),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeHubAppClient({})),
      hubAppOverride(const HubAppState.unavailable()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Riyadh'),
      storeFeaturesProvider.overrideWith((ref) async => StoreFeatures.none),
      freeShippingThresholdProvider.overrideWith((ref) async => null),
    ],
  );
  addTearDown(container.dispose);
  if (remembered != null) {
    await container.read(guestOrderStoreProvider.notifier).remember(remembered);
  }
  final router = container.read(routerProvider)..go(location);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: AppTheme.light('en'),
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
  return router;
}

void main() {
  group('AccountRepository.fetchOrderByNumber', () {
    Map<String, dynamic> page(List<Map<String, dynamic>> items) => {
      'customer': {
        '__typename': 'Customer',
        'orders': {'__typename': 'CustomerOrders', 'items': items},
      },
    };

    Map<String, dynamic> orderJson({bool withSeller = false}) => {
      '__typename': 'CustomerOrder',
      'id': 'MjQ4',
      'number': _number,
      'status': 'Processing',
      'order_date': '2026-09-28 10:42:00',
      'items': [
        {
          '__typename': 'OrderItem',
          'product_name': 'Corner Sofa Bed',
          'product_sku': 'SOFA',
          'quantity_ordered': 1,
          if (withSeller) 'hm_seller': sellerJson('mia', 'MIA CO'),
        },
      ],
    };

    test('filters the customer orders by number', () async {
      final server = RecordingGraphQLClient((_, __) => page([orderJson()]));
      final order = await AccountRepository(
        server.client,
      ).fetchOrderByNumber(_number);

      expect(order?.number, _number);
      expect(order?.lines.single.name, 'Corner Sofa Bed');
      final request = server.requests.single;
      expect(operationNameOf(request), 'CustomerOrderByNumber');
      expect(request.variables, {'number': _number});
      expect(server.documents.single, contains(r'eq: $number'));
      expect(server.documents.single, isNot(contains('hm_seller')));
    });

    test('null when the customer has no such order', () async {
      final server = RecordingGraphQLClient((_, __) => page(const []));
      expect(
        await AccountRepository(server.client).fetchOrderByNumber('999'),
        isNull,
      );
    });

    test('with HubApp the lines carry their seller', () async {
      final server = RecordingGraphQLClient(
        (_, __) => page([orderJson(withSeller: true)]),
      );
      final order = await AccountRepository(
        server.client,
        marketplace: RecordingMarketplaceGate(),
      ).fetchOrderByNumber(_number);

      expect(server.documents.single, contains('hm_seller'));
      expect(order?.lines.single.seller?.name, 'MIA CO');
    });

    test('its HubApp twin still defines every fragment once', () {
      final twin = AccountQueries.withSellers(AccountQueries.orderByNumber);
      expect(AccountQueries.orderByNumber, isNot(contains('hm_')));
      expect(twin, contains('...HmOrderSellers'));
      expect(RegExp('fragment OrderFields').allMatches(twin), hasLength(1));
    });
  });

  group('/orders/<number>', () {
    testWidgets('a customer gets the order, with My Orders beneath', (
      tester,
    ) async {
      final repo = _OrdersRepo();
      final router = await _pumpAt(
        tester,
        AppRoutes.orderByNumber(_number),
        repo: repo,
      );

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('Order #$_number'), findsOneWidget);
      expect(repo.calls, contains('number:$_number'));

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);
    });

    testWidgets('an order the customer does not have: not found', (
      tester,
    ) async {
      await _pumpAt(
        tester,
        AppRoutes.orderByNumber('000000999'),
        repo: _OrdersRepo(),
      );

      expect(find.text('Order not found'), findsOneWidget);
      expect(
        find.text("We couldn't find order #000000999 in your account."),
        findsOneWidget,
      );
      await tester.tap(find.text('My Orders'));
      await tester.pumpAndSettle();
      expect(find.byType(OrdersScreen), findsOneWidget);
    });

    testWidgets('a failed lookup offers Retry', (tester) async {
      final repo = _OrdersRepo(failures: 1);
      await _pumpAt(tester, AppRoutes.orderByNumber(_number), repo: repo);

      expect(
        find.text('Something went wrong. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Order #$_number'), findsOneWidget);
      expect(repo.calls.where((c) => c == 'number:$_number'), hasLength(2));
    });

    testWidgets('a guest goes to Track order with the number filled in', (
      tester,
    ) async {
      final repo = _OrdersRepo();
      await _pumpAt(
        tester,
        AppRoutes.orderByNumber(_number),
        repo: repo,
        signedIn: false,
      );

      expect(find.byType(GuestTrackOrderScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, _number), findsOneWidget);
      expect(repo.calls, isNot(contains('number:$_number')));
    });

    testWidgets('a guest sees an order this device remembers', (tester) async {
      final repo = _OrdersRepo();
      await _pumpAt(
        tester,
        AppRoutes.orderByNumber(_number),
        repo: repo,
        signedIn: false,
        remembered: const GuestOrderRef(number: _number, token: 'tok-248'),
      );

      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.text('Order #$_number'), findsOneWidget);
      expect(repo.calls, contains('token:tok-248'));
      expect(repo.calls, isNot(contains('number:$_number')));
    });
  });

  testWidgets('/order-detail?number= opens the order by its number', (
    tester,
  ) async {
    await _pumpAt(tester, '/order-detail?number=$_number', repo: _OrdersRepo());

    expect(find.text('Order #$_number'), findsOneWidget);
  });

  testWidgets('/order-detail without an order or a number: My Orders', (
    tester,
  ) async {
    await _pumpAt(tester, AppRoutes.orderDetail, repo: _OrdersRepo());

    expect(find.byType(OrdersScreen), findsOneWidget);
  });
}
