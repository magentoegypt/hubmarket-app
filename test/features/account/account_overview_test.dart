import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/account_overview.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

/// What the Account hub (Figma 20) counts and sums from the order history: the
/// Orders tile's "active", and the Shopping stats card — shown only for a
/// history it could read whole.

CustomerOrder _order(
  String number,
  String status,
  double total, {
  String date = '2026-09-28 10:42:00',
  String currency = 'AED',
}) => CustomerOrder(
  number: number,
  status: status,
  date: date,
  total: Money(amount: total, currency: currency),
);

void main() {
  group('summariseOrders', () {
    final history = [
      _order('5', 'Pending', 120), // active
      _order('4', 'Processing', 80, date: '2026-03-02 09:00:00'), // active
      _order('3', 'Complete', 200, date: '2026-01-15 09:00:00'),
      _order('2', 'Canceled', 999, date: '2026-02-01 09:00:00'), // spends nothing
      _order('1', 'Complete', 100, date: '2025-11-20 09:00:00'),
      _order('0', 'Closed', 500, date: '2025-10-01 09:00:00'), // refunded
    ];

    test('counts the orders neither delivered nor cancelled as active', () {
      final overview = summariseOrders(history, complete: true, year: 2026);
      expect(overview.activeCount, 2);
    });

    test('adds up what was not cancelled, and this year\'s share', () {
      final stats = summariseOrders(history, complete: true, year: 2026).stats!;
      // 120 + 80 + 200 + 100: the cancelled and the closed order spent nothing.
      expect(stats.totalSpent, const Money(amount: 500, currency: 'AED'));
      // Placed in 2026 and not cancelled: 5, 4 and 3.
      expect(stats.ordersThisYear, 3);
      expect(stats.averageOrder, const Money(amount: 125, currency: 'AED'));
    });

    test('a history that was not read whole has no stats, only the count', () {
      final overview = summariseOrders(history, complete: false, year: 2026);
      expect(overview.activeCount, 2);
      expect(overview.stats, isNull);
    });

    test('nothing that counts, no stats', () {
      expect(
        summariseOrders(const [], complete: true, year: 2026).stats,
        isNull,
      );
      expect(
        summariseOrders(
          [_order('1', 'Canceled', 50)],
          complete: true,
          year: 2026,
        ).stats,
        isNull,
      );
    });

    test('one market, one currency: a mixed history has no stats', () {
      final mixed = [_order('2', 'Complete', 50), _order('1', 'Complete', 9, currency: 'USD')];
      expect(summariseOrders(mixed, complete: true, year: 2026).stats, isNull);
    });
  });

  group('AccountRepository.fetchOrderDigests', () {
    test('reads the digest rows: number, date, status, grand total', () async {
      final client = fakeHubAppClient({
        'CustomerOrderDigests': {
          'customer': {
            'orders': {
              'total_count': 2,
              'page_info': {'current_page': 1, 'total_pages': 1},
              'items': [
                {
                  'number': '000000248',
                  'order_date': '2026-09-28 10:42:00',
                  'status': 'Pending',
                  'total': {
                    'grand_total': {'value': 553.0, 'currency': 'AED'},
                  },
                },
                {
                  'number': '000000231',
                  'order_date': '2026-09-20 18:00:00',
                  'status': 'Complete',
                  'total': {
                    'grand_total': {'value': 23.5, 'currency': 'AED'},
                  },
                },
              ],
            },
          },
        },
      });
      final page = await AccountRepository(client).fetchOrderDigests();
      expect(page.totalCount, 2);
      expect(page.items.map((o) => o.number), ['000000248', '000000231']);
      expect(page.items.first.status, 'Pending');
      expect(page.items.first.date, '2026-09-28 10:42:00');
      expect(
        page.items.first.total,
        const Money(amount: 553, currency: 'AED'),
      );
      // The whole customer's history, on the website scope, newest first —
      // not the heavy order document.
      final sent = client.requests.single.operation.document.toString();
      expect(sent, isNot(contains('product_name')));
    });
  });

  group('accountOrdersOverviewProvider', () {
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
      final account = _DigestRepository([_order('1', 'Complete', 10)]);
      final c = await container(account, signedIn: false);
      expect(await c.read(accountOrdersOverviewProvider.future), isNull);
      expect(account.pagesAsked, isEmpty);
    });

    test('reads every page, then sums the whole history', () async {
      final orders = [
        for (var i = 120; i >= 1; i--)
          _order('$i', 'Complete', 10, date: '${DateTime.now().year}-01-02 10:00:00'),
      ];
      final account = _DigestRepository(orders);
      final c = await container(account);
      final overview = (await c.read(accountOrdersOverviewProvider.future))!;
      // 50 per page: three requests for 120 orders.
      expect(account.pagesAsked, [1, 2, 3]);
      expect(overview.stats!.totalSpent.amount, 1200);
      expect(overview.stats!.ordersThisYear, 120);
    });

    test('a history too long to add up shows no stats card', () async {
      final orders = [
        for (var i = 400; i >= 1; i--) _order('$i', 'Complete', 10),
      ];
      final account = _DigestRepository(orders);
      final c = await container(account);
      final overview = (await c.read(accountOrdersOverviewProvider.future))!;
      // It stops at kOverviewMaxOrders and says so by leaving the card out.
      expect(account.pagesAsked.length, kOverviewMaxOrders ~/ 50);
      expect(overview.stats, isNull);
      expect(overview.activeCount, 0);
    });

    test('a failing request is a null overview, not an error', () async {
      final account = _DigestRepository(const [])..fails = true;
      final c = await container(account);
      expect(await c.read(accountOrdersOverviewProvider.future), isNull);
    });
  });
}

/// Serves [orders] (newest first) in the pages the digest query asks for.
class _DigestRepository extends FakeAccountRepository {
  _DigestRepository(this.history);

  final List<CustomerOrder> history;
  final List<int> pagesAsked = [];
  bool fails = false;

  @override
  Future<OrderPage> fetchOrderDigests({
    int pageSize = 50,
    int currentPage = 1,
  }) async {
    pagesAsked.add(currentPage);
    if (fails) throw Exception('offline');
    final from = (currentPage - 1) * pageSize;
    final items = history.skip(from).take(pageSize).toList();
    return OrderPage(
      items: items,
      currentPage: currentPage,
      totalPages: (history.length / pageSize).ceil(),
      totalCount: history.length,
    );
  }
}
