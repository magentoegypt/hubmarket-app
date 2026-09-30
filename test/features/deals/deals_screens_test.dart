import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/deals/data/deals_repository.dart';
import 'package:hubmarket_app/features/deals/domain/deals.dart';
import 'package:hubmarket_app/features/deals/presentation/screens/bundle_deals_screen.dart';
import 'package:hubmarket_app/features/deals/presentation/screens/deals_screen.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

const _grocery = DealCategory(id: 3, uid: 'Mw==', name: 'Grocery', count: 0);
const _furniture = DealCategory(id: 5, uid: 'NQ==', name: 'Furniture', count: 0);

/// A deal as the server ranks it: its product, department and discount.
typedef _Deal = ({Product product, DealCategory category, int percent});

_Deal _deal(
  String name,
  double price,
  double was,
  DealCategory category,
) => (
  product: Product(
    sku: name,
    name: name,
    urlKey: name.toLowerCase().replaceAll(' ', '-'),
    regularPrice: Money(amount: was, currency: 'AED'),
    finalPrice: Money(amount: price, currency: 'AED'),
  ),
  category: category,
  percent: ((was - price) * 100 / was).round(),
);

/// The day's ranking, deepest discount first (29 %, 25 %, 15 %, 10 %, 10 %).
final _deals = <_Deal>[
  _deal('Egyptian Rice 1 kg', 25, 35, _grocery),
  _deal('Modern Executive Desk', 263, 350, _furniture),
  _deal('Corner Sofa Bed', 425, 500, _furniture),
  _deal('Dolphin Tuna', 43, 48, _grocery),
  _deal('Velvet Armchair', 180, 200, _furniture),
];

BundleDeal _bundle(
  String name, {
  int percent = 16,
  String? seller = 'Test 1',
}) => BundleDeal(
  uid: name,
  sku: name,
  name: name,
  urlKey: name.toLowerCase().replaceAll(' ', '-'),
  price: const Money(amount: 61, currency: 'AED'),
  regularTotal: const Money(amount: 72, currency: 'AED'),
  saving: const Money(amount: 11, currency: 'AED'),
  discountPercent: percent,
  itemCount: 4,
  ratingPercent: 90,
  reviewCount: 12,
  seller: seller == null ? null : HmSellerSummary(name: seller),
);

/// The server of hmDeals: filters and sorts the whole ranking, counts the
/// departments of every filter but the category, pages of [perPage].
class _FakeDeals implements DealsRepository {
  _FakeDeals({this.missing = false, this.older = false, this.perPage = 20});

  final bool missing;

  /// A HubApp older than the filters: the plain ranking.
  final bool older;
  final int perPage;
  final List<int?> bundleCategories = [];
  final List<int> dealPages = [];
  final List<DealsFilters> asked = [];

  @override
  Future<DealsPage> fetchDeals({
    int pageSize = 20,
    int currentPage = 1,
    DealsFilters filters = const DealsFilters(),
  }) async {
    if (missing) throw const HubAppMissing('Cannot query field "hmDeals"');
    dealPages.add(currentPage);
    asked.add(filters);
    final offered = [
      for (final d in _deals)
        if (older || d.percent >= (filters.minDiscount ?? 0)) d,
    ];
    final matching = [
      for (final d in offered)
        if (older ||
            filters.categoryId == null ||
            d.category.id == filters.categoryId)
          d,
    ];
    double price(_Deal d) => d.product.finalPrice!.amount;
    if (!older) {
      switch (filters.sort) {
        case DealsSort.priceLowHigh:
          matching.sort((a, b) => price(a).compareTo(price(b)));
        case DealsSort.priceHighLow:
          matching.sort((a, b) => price(b).compareTo(price(a)));
        default:
      }
    }
    final start = (currentPage - 1) * perPage;
    final page = matching.skip(start).take(perPage).toList();
    final counts = <int, int>{};
    for (final d in offered) {
      counts[d.category.id] = (counts[d.category.id] ?? 0) + 1;
    }
    return DealsPage(
      items: [for (final d in page) d.product],
      totalCount: matching.length,
      pageInfo: HmPageInfo(
        currentPage: currentPage,
        pageSize: perPage,
        totalPages: (matching.length / perPage).ceil(),
      ),
      countdownEndsAt: DateTime.now().add(
        const Duration(days: 2, hours: 14, minutes: 32, seconds: 19),
      ),
      categories: older || counts.length < 2
          ? const <DealCategory>[]
          : [
              for (final c in [_grocery, _furniture])
                if (counts[c.id] case final count?)
                  DealCategory(
                    id: c.id,
                    uid: c.uid,
                    name: c.name,
                    count: count,
                  ),
            ],
      filtered: !older,
    );
  }

  @override
  Future<BundleDealPage> fetchBundleDeals({
    int? categoryId,
    int pageSize = 20,
    int currentPage = 1,
  }) async {
    if (missing) {
      throw const HubAppMissing('Cannot query field "hmBundleDeals"');
    }
    bundleCategories.add(categoryId);
    final items = categoryId == 7
        ? [_bundle('Home Fitness Starter Pack')]
        : [
            _bundle('Home Fitness Starter Pack'),
            _bundle(
              'House Tools Set',
              percent: 15,
              seller: 'Future Building Materials',
            ),
          ];
    return BundleDealPage(
      items: items,
      categories: const [
        DealCategory(id: 7, uid: 'Nw==', name: 'Fitness', count: 1),
        DealCategory(id: 13, uid: 'MTM=', name: 'Electronics & Tech', count: 1),
      ],
      maxDiscountPercent: 16,
      sellerCount: 3,
      totalCount: items.length,
    );
  }
}

Widget _harness(
  Widget screen, {
  required _FakeDeals deals,
  String locale = 'en',
  GlobalKey? boundary,
  HmHome? home,
}) {
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
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, s) =>
            Scaffold(body: Text('PDP ${s.pathParameters['urlKey']}')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(const HubAppState.available(kSampleHmAppConfig)),
      dealsRepositoryProvider.overrideWithValue(deals),
      if (home != null) hmHomeProvider.overrideWith((ref) async => home),
    ],
    child: RepaintBoundary(
      key: boundary,
      child: MaterialApp.router(
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
      ),
    ),
  );
}

Future<void> _phone(WidgetTester tester, {double height = 844}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(loadAppFonts);

  group("Today's Deals (10b)", () {
    for (final locale in ['en', 'ar']) {
      testWidgets('banner, chips, count, sort, filters and grid ($locale)', (
        tester,
      ) async {
        await _phone(tester, height: 1100);
        final key = GlobalKey();
        final deals = _FakeDeals();
        await tester.pumpWidget(
          _harness(
            const DealsScreen(),
            deals: deals,
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'deals_$locale');

        final l10n = AppLocalizations.of(
          tester.element(find.byType(DealsScreen)),
        );
        expect(find.text(l10n.homeTodaysDeals), findsOneWidget);
        expect(find.text(l10n.dealsEndIn), findsOneWidget);
        // No promise about when deals refresh (QA02).
        expect(
          find.textContaining(locale == 'ar' ? 'منتصف الليل' : 'midnight'),
          findsNothing,
        );
        expect(find.text(l10n.dealsCount(5)), findsOneWidget);
        expect(find.text(l10n.dealsAllChip), findsOneWidget);
        // The server's department chips, catalogue order.
        expect(find.text('Grocery'), findsOneWidget);
        expect(find.text('Furniture'), findsOneWidget);
        expect(find.text(l10n.dealsSortBiggestDiscount), findsOneWidget);
        expect(find.text(l10n.filtersLabel), findsOneWidget);
        // The ranking as the server sent it: one request, nothing re-sorted.
        expect(deals.asked, [const DealsFilters()]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a chip asks the server for that department; the chips stay', (
      tester,
    ) async {
      await _phone(tester, height: 1600);
      final deals = _FakeDeals();
      await tester.pumpWidget(_harness(const DealsScreen(), deals: deals));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grocery'));
      await tester.pumpAndSettle();

      expect(deals.asked.last, const DealsFilters(categoryId: 3));
      expect(find.text('2 deals'), findsOneWidget);
      expect(find.text('Corner Sofa Bed'), findsNothing);
      expect(find.text('Dolphin Tuna'), findsOneWidget);
      expect(find.text('Furniture'), findsOneWidget);

      await tester.tap(find.text('All deals'));
      await tester.pumpAndSettle();
      expect(deals.asked.last, const DealsFilters());
      expect(find.text('5 deals'), findsOneWidget);
    });

    testWidgets('the sort pill reorders on the server', (tester) async {
      await _phone(tester, height: 1600);
      final deals = _FakeDeals();
      await tester.pumpWidget(_harness(const DealsScreen(), deals: deals));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Biggest discount'));
      await tester.pumpAndSettle();
      // Every order the server offers.
      expect(find.text('Ending soon'), findsOneWidget);
      expect(find.text('Newest First'), findsOneWidget);
      await tester.tap(find.text('Price: Low to High'));
      await tester.pumpAndSettle();

      expect(deals.asked.last.sort, DealsSort.priceLowHigh);
      final rice = tester.getTopLeft(find.text('Egyptian Rice 1 kg'));
      final tuna = tester.getTopLeft(find.text('Dolphin Tuna'));
      expect(rice.dy, tuna.dy); // AED 25 and 43: the first row
      expect(rice.dx, lessThan(tuna.dx));
      expect(find.text('Price: Low to High'), findsOneWidget);
    });

    for (final locale in ['en', 'ar']) {
      testWidgets('the Filters sheet: sort, minimum discount, department '
          '($locale)', (tester) async {
        await _phone(tester, height: 1000);
        final key = GlobalKey();
        final deals = _FakeDeals();
        await tester.pumpWidget(
          _harness(
            const DealsScreen(),
            deals: deals,
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(DealsScreen)),
        );

        await tester.tap(find.text(l10n.filtersLabel));
        await tester.pumpAndSettle();
        expect(find.byType(DealsFilterSheet), findsOneWidget);
        await tester.tap(find.text(l10n.dealsSortEndingSoon).last);
        await tester.tap(find.text(l10n.filterDiscountOption(20)));
        // The chips count the department's deals as the list stands.
        await tester.tap(find.text('Furniture (3)'));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'deals_filters_$locale');

        await tester.tap(find.text(l10n.filterApplyLabel));
        await tester.pumpAndSettle();

        expect(
          deals.asked.last,
          const DealsFilters(
            categoryId: 5,
            minDiscount: 20,
            sort: DealsSort.endingSoon,
          ),
        );
        expect(find.text('${l10n.filtersLabel} · 2'), findsOneWidget);
        // Furniture with 20% or more off: the desk alone.
        expect(find.text(l10n.dealsCount(1)), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('filters that leave nothing: say so, and clear them', (
      tester,
    ) async {
      await _phone(tester, height: 1000);
      final deals = _FakeDeals();
      await tester.pumpWidget(_harness(const DealsScreen(), deals: deals));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('50% or more'));
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();

      expect(find.text('No deals match these filters.'), findsOneWidget);
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();
      expect(deals.asked.last, const DealsFilters());
      expect(find.text('5 deals'), findsOneWidget);
    });

    testWidgets('more deals load as the list scrolls', (tester) async {
      await _phone(tester);
      final deals = _FakeDeals(perPage: 3);
      await tester.pumpWidget(_harness(const DealsScreen(), deals: deals));
      await tester.pumpAndSettle();
      expect(deals.dealPages, [1]);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(deals.dealPages, [1, 2]);
    });

    testWidgets('an older HubApp: the ranking without chips, sort or filters', (
      tester,
    ) async {
      await _phone(tester, height: 1600);
      await tester.pumpWidget(
        _harness(const DealsScreen(), deals: _FakeDeals(older: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('5 deals'), findsOneWidget);
      expect(find.text('Grocery'), findsNothing);
      expect(find.text('Biggest discount'), findsNothing);
      expect(find.text('Filters'), findsNothing);
      expect(find.text('Egyptian Rice 1 kg'), findsOneWidget);
    });

    testWidgets('without the Hub Market App API: the empty state', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(const DealsScreen(), deals: _FakeDeals(missing: true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No deals today — check back tomorrow.'),
        findsOneWidget,
      );
    });
  });

  group('Bundle deals (10c)', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('intro stats, chips and bundle cards ($locale)', (
        tester,
      ) async {
        await _phone(tester, height: 1300);
        final key = GlobalKey();
        await tester.pumpWidget(
          _harness(
            const BundleDealsScreen(),
            deals: _FakeDeals(),
            locale: locale,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'bundles_$locale');

        final l10n = AppLocalizations.of(
          tester.element(find.byType(BundleDealsScreen)),
        );
        // Neutral interface wording: the Home hasn't named the section.
        expect(find.text(l10n.bundlesHeroTitle), findsOneWidget);
        expect(find.text(l10n.bundlesHeroBody), findsOneWidget);
        expect(find.text(l10n.bundlesStatUpTo(16)), findsOneWidget);
        expect(find.text('3'), findsOneWidget); // vendors
        expect(find.text('House Tools Set'), findsOneWidget);
        expect(
          find.textContaining(l10n.bundleSoldBy('Test 1')),
          findsOneWidget,
        );
        expect(find.text(l10n.bundleAdd), findsNWidgets(2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the intro takes the admin\'s bundles title and subtitle '
        'from the Home layout', (tester) async {
      await _phone(tester, height: 1300);
      const home = HmHome(
        storeCode: 'en',
        sections: [
          HmHomeSection(
            id: 7,
            type: HmSectionType.bundleDeals,
            title: 'Ramadan Bundles',
            subtitle: 'Packs put together by our sellers',
          ),
        ],
      );
      await tester.pumpWidget(
        _harness(
          // Home read the layout first; the list never loads it itself.
          Consumer(
            builder: (_, ref, __) {
              ref.watch(hmHomeProvider);
              return const BundleDealsScreen();
            },
          ),
          deals: _FakeDeals(),
          home: home,
        ),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.text('Ramadan Bundles'), findsOneWidget);
      expect(find.text('Packs put together by our sellers'), findsOneWidget);
      expect(find.text(l10n.bundlesHeroTitle), findsNothing);
      expect(find.text(l10n.bundlesHeroBody), findsNothing);
    });

    testWidgets('a chip reloads that category from the server', (tester) async {
      await _phone(tester, height: 1300);
      final deals = _FakeDeals();
      await tester.pumpWidget(
        _harness(const BundleDealsScreen(), deals: deals),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fitness'));
      await tester.pumpAndSettle();

      expect(deals.bundleCategories, [null, 7]);
      expect(find.text('House Tools Set'), findsNothing);
      // The chips stay while one is selected.
      expect(find.text('Electronics & Tech'), findsOneWidget);

      await tester.tap(find.text('Add Bundle').first);
      await tester.pumpAndSettle();
      expect(find.text('PDP home-fitness-starter-pack'), findsOneWidget);
    });

    testWidgets('without the Hub Market App API: the empty state', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(const BundleDealsScreen(), deals: _FakeDeals(missing: true)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No bundle deals right now.'), findsOneWidget);
    });
  });
}
