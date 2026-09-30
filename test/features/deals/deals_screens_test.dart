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

const _grocery = ProductCategoryRef(uid: 'Mw==', name: 'Grocery', level: 2);
const _furniture = ProductCategoryRef(uid: 'NQ==', name: 'Furniture', level: 2);

Product _deal(
  String name,
  double price,
  double was,
  ProductCategoryRef category,
) => Product(
  sku: name,
  name: name,
  urlKey: name.toLowerCase().replaceAll(' ', '-'),
  regularPrice: Money(amount: was, currency: 'AED'),
  finalPrice: Money(amount: price, currency: 'AED'),
  categories: [category],
);

final _deals = <Product>[
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

class _FakeDeals implements DealsRepository {
  _FakeDeals({this.missing = false});

  final bool missing;
  final List<int?> bundleCategories = [];
  final List<int> dealPages = [];

  @override
  Future<DealsPage> fetchDeals({int pageSize = 20, int currentPage = 1}) async {
    if (missing) throw const HubAppMissing('Cannot query field "hmDeals"');
    dealPages.add(currentPage);
    return DealsPage(
      items: currentPage == 1
          ? _deals.take(3).toList()
          : _deals.skip(3).toList(),
      totalCount: _deals.length,
      pageInfo: HmPageInfo(
        currentPage: currentPage,
        pageSize: 3,
        totalPages: 2,
      ),
      countdownEndsAt: DateTime.now().add(
        const Duration(days: 2, hours: 14, minutes: 32, seconds: 19),
      ),
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
      testWidgets('banner, chips, count, sort and grid ($locale)', (
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
        expect(find.text(l10n.dealsNewEveryDay), findsNothing);
        expect(find.text(l10n.dealsCount(5)), findsOneWidget);
        expect(find.text(l10n.dealsAllChip), findsOneWidget);
        // Chips from the deals' own top-level categories, busiest first.
        expect(find.text('Furniture'), findsOneWidget);
        expect(find.text('Grocery'), findsOneWidget);
        // Both pages were read.
        expect(deals.dealPages, [1, 2]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a chip filters and a sort reorders, on the whole list', (
      tester,
    ) async {
      await _phone(tester, height: 1600);
      await tester.pumpWidget(
        _harness(const DealsScreen(), deals: _FakeDeals()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grocery'));
      await tester.pumpAndSettle();
      expect(find.text('2 deals'), findsOneWidget);
      expect(find.text('Corner Sofa Bed'), findsNothing);
      expect(find.text('Dolphin Tuna'), findsOneWidget);

      await tester.tap(find.text('Biggest discount'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Price: Low to High'));
      await tester.pumpAndSettle();
      final rice = tester.getTopLeft(find.text('Egyptian Rice 1 kg'));
      final tuna = tester.getTopLeft(find.text('Dolphin Tuna'));
      expect(rice.dx, lessThan(tuna.dx)); // AED 25 before AED 43
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
