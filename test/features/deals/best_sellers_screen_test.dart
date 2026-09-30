import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/best_sellers_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/search_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/search_no_results.dart';
import 'package:hubmarket_app/features/deals/presentation/screens/best_sellers_screen.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_view.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

Product _product(int rank) => Product(
  sku: 'sku-$rank',
  name: 'Product $rank',
  urlKey: 'product-$rank',
  regularPrice: Money(amount: 10.0 + rank, currency: 'AED'),
  finalPrice: Money(amount: 10.0 + rank, currency: 'AED'),
);

/// 25 best sellers, 20 a page.
class _FakeBestSellers implements BestSellersRepository {
  _FakeBestSellers({this.missing = false});

  final bool missing;
  final List<int> pages = <int>[];

  static const int total = 25;

  @override
  Future<BestSellersPage> fetchPage({
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    if (missing) {
      throw const HubAppMissing('Cannot query field "hmBestSellers"');
    }
    pages.add(currentPage);
    final start = (currentPage - 1) * pageSize;
    return BestSellersPage(
      items: [
        for (var i = start; i < math.min(start + pageSize, total); i++)
          _product(i + 1),
      ],
      totalCount: total,
      pageInfo: HmPageInfo(
        currentPage: currentPage,
        pageSize: pageSize,
        totalPages: (total / pageSize).ceil(),
      ),
    );
  }

  @override
  Future<List<Product>> fetch({int pageSize = 10}) async =>
      (await fetchPage(pageSize: pageSize)).items;
}

/// [screen] in a router that records where it goes.
Future<List<String>> _pump(
  WidgetTester tester,
  Widget screen, {
  _FakeBestSellers? bestSellers,
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  List<Override> overrides = const [],
  double height = 1000,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final visited = <String>[];
  Widget stub(BuildContext _, GoRouterState state) {
    visited.add(state.uri.toString());
    return Scaffold(body: Text('route ${state.uri}'));
  }

  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
        '/search',
        '/stores',
        AppRoutes.bestSellers,
        '/product/:urlKey',
      ])
        GoRoute(path: p, builder: stub),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        hubAppOverride(hubApp),
        bestSellersRepositoryProvider.overrideWithValue(
          bestSellers ?? _FakeBestSellers(),
        ),
        ...overrides,
      ],
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
  return visited;
}

void main() {
  group('Best sellers page', () {
    testWidgets('ranks the products and reads the next page on scroll', (
      tester,
    ) async {
      final repo = _FakeBestSellers();
      final visited = await _pump(
        tester,
        const BestSellersScreen(),
        bestSellers: repo,
      );

      expect(find.text('Best Sellers'), findsOneWidget);
      expect(find.text('25 products'), findsOneWidget);
      expect(find.text('#1 Best seller'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(repo.pages, [1]);

      final list = find.descendant(
        of: find.byType(BestSellersScreen),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Product 25'),
        400,
        scrollable: list.first,
      );
      await tester.pumpAndSettle();
      expect(repo.pages, [1, 2]);
      expect(find.text('#25'), findsOneWidget);

      await tester.tap(find.text('Product 25'));
      await tester.pumpAndSettle();
      expect(visited.last, '/product/product-25');
    });

    testWidgets('a server without hmBestSellers: the empty state', (
      tester,
    ) async {
      await _pump(
        tester,
        const BestSellersScreen(),
        bestSellers: _FakeBestSellers(missing: true),
      );

      expect(
        find.text('No best sellers yet — check back soon.'),
        findsOneWidget,
      );
    });
  });

  group('BestSellersRepository.fetchPage', () {
    test('asks for the page and reads its paging', () async {
      final client = fakeHubAppClient({
        'HmBestSellers': {
          'hmBestSellers': {
            'total_count': 45,
            'page_info': {'current_page': 2, 'page_size': 20, 'total_pages': 3},
            'items': [
              {
                '__typename': 'SimpleProduct',
                'sku': 'a',
                'name': 'A',
                'url_key': 'a',
                'price_range': null,
              },
              // Nothing to open: left out.
              {'__typename': 'SimpleProduct', 'sku': 'b', 'name': 'B'},
            ],
          },
        },
      });
      final page = await BestSellersRepository(
        client,
      ).fetchPage(pageSize: 20, currentPage: 2);

      expect(client.requests.single.variables, {
        'pageSize': 20,
        'currentPage': 2,
      });
      expect(page.items.map((p) => p.urlKey), ['a']);
      expect(page.totalCount, 45);
      expect(page.pageInfo.currentPage, 2);
      expect(page.pageInfo.hasMore, isTrue);
    });
  });

  group('"View All" leads to the best sellers', () {
    final section = HmHomeSection(
      id: 11,
      type: HmSectionType.bestSellers,
      title: 'Best Selling Items',
      products: [_product(1), _product(2)],
    );

    testWidgets('from the Home section without an admin link', (tester) async {
      final visited = await _pump(
        tester,
        Scaffold(body: HmSectionView(section: section)),
      );

      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();
      expect(visited.last, AppRoutes.bestSellers);
    });

    testWidgets('not without the Hub Market App', (tester) async {
      await _pump(
        tester,
        Scaffold(body: HmSectionView(section: section)),
        hubApp: const HubAppState.unknown(),
      );

      expect(find.text('Best Selling Items'), findsOneWidget);
      expect(find.text('View All'), findsNothing);
    });

    testWidgets('from the no-results page\'s "Popular right now"', (
      tester,
    ) async {
      final visited = await _pump(
        tester,
        const Scaffold(body: SearchNoResults(query: 'zzz')),
        overrides: [
          searchPopularNowProvider.overrideWith(
            (ref) async => [_product(1), _product(2)],
          ),
        ],
        height: 1200,
      );

      expect(find.text('Popular right now'), findsOneWidget);
      await tester.tap(find.text('View All'));
      await tester.pumpAndSettle();
      expect(visited.last, AppRoutes.bestSellers);
    });

    testWidgets('the no-results page without HubApp has no rail', (
      tester,
    ) async {
      await _pump(
        tester,
        const Scaffold(body: SearchNoResults(query: 'zzz')),
        hubApp: const HubAppState.unavailable(),
        overrides: [
          searchPopularNowProvider.overrideWith(
            (ref) async => [_product(1), _product(2)],
          ),
        ],
      );

      expect(find.text('Popular right now'), findsNothing);
      expect(find.text('View All'), findsNothing);
    });
  });
}
