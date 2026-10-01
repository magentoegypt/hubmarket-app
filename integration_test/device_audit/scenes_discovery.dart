import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/data/brands_provider.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/presentation/catalog_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/brand_page_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/brands_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/categories_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/search_providers.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/filter_sheet.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/sheet_chrome.dart';
import 'package:hubmarket_app/features/deals/data/deals_repository.dart';
import 'package:hubmarket_app/features/deals/presentation/screens/bundle_deals_screen.dart';
import 'package:hubmarket_app/features/deals/presentation/screens/deals_screen.dart';
import 'package:hubmarket_app/features/home/data/hm_home_repository.dart';
import 'package:hubmarket_app/features/home/domain/hm_home.dart';
import 'package:hubmarket_app/features/home/presentation/hm_home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../test/features/home/hm_home_fixtures.dart' as home_fixtures;
import '../../test/support/algolia_fakes.dart';
import '../../test/support/fakes.dart';
import '../../test/support/hubapp_fakes.dart';
import '../../test/support/search_fixtures.dart';
import '../../test/support/store_fixtures.dart';
import '../../test/features/stores/stores_harness.dart';
import 'audit_scene.dart';
import 'discovery_fixtures.dart';
import 'harness.dart';

/// Discovery: B07 Home (the Hub Market App layout and the storefront-blocks
/// layout), B08 Categories, B09 Search type-ahead, B09b Search landing, B09c
/// Search results, B10 PLP, B10b Deals, B10c Bundles, B10d Brands, B10e Brand
/// page, B11 Filters / sort sheets, F_S2 No results.
///
/// One scene per frame state, ported from the widget test that renders it (see
/// docs/ui-audit.md, `PAIRS` in tool/ui_audit/pairs.py names the captures).
/// The fixtures are in discovery_fixtures.dart.
List<AuditScene> scenes() => [
  // ---------------------------------------------------------------- B07 Home
  // Both Homes, signed in with an open order, an unread notification and recent
  // searches: everything the frame draws (test/features/home/home_audit_test.dart).
  // The frame is 6313 px tall: four further screens of the scroll.
  AuditScene(
    frame: 'B07_home',
    name: 'hubapp',
    screen: (_) =>
        InboxScope(items: homeUnreadInbox(), child: const HubHomeScreen()),
    setup: (locale) => _homeSetup(locale, hubApp: true),
    pushed: false,
    scrolls: 4,
  ),
  AuditScene(
    frame: 'B07_home',
    name: 'build1',
    screen: (_) =>
        InboxScope(items: homeUnreadInbox(), child: const HubHomeScreen()),
    setup: (locale) => _homeSetup(locale, hubApp: false),
    pushed: false,
    scrolls: 4,
  ),

  // ---------------------------------------------------------- B08 Categories
  // The frame has Furniture picked
  // (test/features/catalog/presentation/categories_screen_test.dart).
  AuditScene(
    frame: 'B08_categories',
    name: 'default',
    screen: (_) => const CategoriesScreen(),
    setup: (locale) => AuditSetup(
      hubApp: const HubAppState.available(kVendorsHmAppConfig),
      overrides: [
        catalogRepositoryProvider.overrideWithValue(
          FakeCatalogRepository(categories: categoriesTree(locale)),
        ),
        publicGraphqlClientProvider.overrideWithValue(
          FakeStoresBackend(categoriesStoresAnswer(locale)).client,
        ),
      ],
    ),
    act: (tester, locale) async {
      await tester.tap(find.text(locale == 'ar' ? 'أثاث' : 'Furniture').first);
      await pumpFor(tester, 500);
    },
    pushed: false,
    // The frame fits "Top stores" in its 844 px, the phone's screen is shorter.
    scrolls: 1,
  ),

  // ------------------------------------------------------------------ Search
  // test/features/catalog/presentation/search_screens_render_test.dart
  // B09 type-ahead: "sofa" typed into the field, the Algolia fake answers.
  AuditScene(
    frame: 'B09_search',
    name: 'default',
    screen: (_) => const SearchScreen(),
    setup: (locale) => _searchSetup(
      locale,
      algolia: FakeAlgoliaBackend(
        answer: withoutImages(sofaAnswers(store: locale)),
      ),
      hubApp: false,
    ),
    act: (tester, locale) async {
      await tester.enterText(
        find.byType(TextField),
        locale == 'ar' ? 'كنبة' : 'sofa',
      );
      await pumpFor(tester, 900);
      await _unfocus(tester);
    },
  ),
  // B09b landing: recent searches, trending searches, popular categories.
  AuditScene(
    frame: 'B09b_search_landing',
    name: 'default',
    screen: (_) => const SearchScreen(),
    setup: (locale) {
      final tree = searchPopularTree(locale);
      final cache = FakeLocalCache()
        ..writeString('search_history', jsonEncode(searchRecents(locale)));
      return _searchSetup(
        locale,
        algolia: FakeAlgoliaBackend(
          answer: withoutImages(sofaAnswers(store: locale)),
        ),
        hubApp: true,
        tree: tree,
        cache: cache,
        home: searchHomeWithChips(tree),
      );
    },
    act: (tester, locale) async => _unfocus(tester),
  ),
  // B09c results for "sofa" with the Hub Market App (vendors, store card).
  AuditScene(
    frame: 'B09c_search_results',
    name: 'default',
    screen: (locale) =>
        SearchScreen(initialQuery: locale == 'ar' ? 'كنبة' : 'sofa'),
    setup: (locale) => _searchSetup(
      locale,
      algolia: FakeAlgoliaBackend(answer: searchAnswers(locale)),
      hubApp: true,
    ),
  ),
  // F_S2 no results: a long query nothing matches; "Popular right now" and the
  // store's query suggestions.
  AuditScene(
    frame: 'F_S2_no_results',
    name: 'default',
    screen: (_) => const SearchScreen(),
    setup: (locale) => _searchSetup(
      locale,
      algolia: FakeAlgoliaBackend(
        answer: searchAnswers(locale, products: false),
      ),
      hubApp: true,
      // The store's query-suggestions index, which Hub Market has not switched
      // on yet (see `searchTrySuggestionsProvider`): the frame shows it on.
      tries: locale == 'ar'
          ? const ['كنبة سرير', 'كنبة خضراء', 'أثاث']
          : const ['sofa bed', 'green sofa', 'Furniture'],
    ),
    act: (tester, locale) async {
      await tester.enterText(
        find.byType(TextField),
        locale == 'ar' ? 'كنبة سرير مخمل أخضر' : 'sofa bed velvet green',
      );
      await pumpFor(tester, 900);
      await _unfocus(tester);
    },
  ),

  // ----------------------------------------------------------------- B10 PLP
  // Home Furniture with MIA CO picked in the Filters sheet, sorted by relevance
  // (test/features/catalog/presentation/plp_render_test.dart).
  AuditScene(
    frame: 'B10_plp',
    name: 'default',
    screen: (locale) => PlpScreen(
      categoryUid: kHomeFurnitureUid,
      title: locale == 'ar' ? 'أثاث منزلي' : 'Home Furniture',
    ),
    setup: _plpSetup,
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tester.tap(find.text(l10n.filtersLabel));
      await pumpFor(tester, 600);
      await tester.tap(
        find.descendant(
          of: find.byType(FilterSheet),
          matching: find.text(locale == 'ar' ? 'ميا كو' : 'MIA CO'),
        ),
      );
      await pumpFor(tester, 900);
      await tester.tap(find.text(l10n.filterShowResults(12)));
      await pumpFor(tester, 600);
      // The frame sorts by relevance (the listing opens on the highest price).
      await tester.tap(find.text(l10n.sortHighestPrice));
      await pumpFor(tester, 600);
      await tester.tap(find.text(l10n.sortRelevance));
      await pumpFor(tester, 600);
    },
  ),

  // ------------------------------------------------------------ B10b Deals
  // Today's Deals: banner, chips, count, sort, filters and the grid
  // (test/features/deals/deals_screens_test.dart).
  AuditScene(
    frame: 'B10b_deals',
    name: 'default',
    screen: (_) => const DealsScreen(),
    setup: (_) => _dealsSetup(),
  ),

  // ----------------------------------------------------------- B10c Bundles
  // Bundle deals: intro stats, chips and the bundle cards.
  AuditScene(
    frame: 'B10c_bundles',
    name: 'default',
    screen: (_) => const BundleDealsScreen(),
    setup: (_) => _dealsSetup(),
  ),

  // ------------------------------------------------------------ B10d Brands
  // All brands: the brands with products, A-Z, with counts
  // (test/features/catalog/presentation/brand_screens_test.dart).
  AuditScene(
    frame: 'B10d_brands',
    name: 'default',
    screen: (_) => const BrandsScreen(),
    setup: (_) => _brandsSetup(),
  ),

  // ------------------------------------------------------- B10e Brand page
  // Samsung: header, category chips, sort and the grid.
  AuditScene(
    frame: 'B10e_brand_page',
    name: 'default',
    screen: (_) => BrandPageScreen(urlKey: 'samsung', brand: brandsList.first),
    setup: (_) => _brandsSetup(),
  ),

  // ------------------------------------------------------------ B11 Filters
  // The Filters sheet of the listing in the frame's state (store MIA CO and size
  // M picked, price 30-450, 4 stars and up), opened over an empty page as the
  // test does (plp_render_test.dart). The shipping listing leaves the rating
  // section out (`kRatingFilterSupported` is off) and the frame has it, so the
  // sheet is built by hand; the empty page behind it keeps the sheet the only
  // vertical scrollable, which is the one the scrolled capture moves. The
  // sheet is 963 px tall in the frame; a phone shows it in two screens.
  AuditScene(
    frame: 'B11_filters',
    name: 'filters',
    screen: (_) => const Scaffold(backgroundColor: Colors.white),
    setup: _plpSetup,
    pushed: false,
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      unawaited(
        showCatalogSheet<Object>(
          context: tester.element(find.byType(Scaffold)),
          builder: (_) => FilterSheet(
            // The listing leaves its own category out of the sheet.
            aggregations: [
              for (final facet in listingAggregations(locale))
                if (facet.attributeCode != 'category_uid') facet,
            ],
            initial: const {
              'VENDORID': {'522'},
              'clothes_size': {'302'},
            },
            currency: 'AED',
            initialPriceFrom: 30,
            initialPriceTo: 450,
            initialMinRating: 4,
            showRating: true,
            sortChoices: [
              (value: ProductSortField.relevance, label: l10n.sortRelevance),
              (value: ProductSortField.priceAsc, label: l10n.sortLowestPrice),
              (value: ProductSortField.priceDesc, label: l10n.sortHighestPrice),
            ],
            initialSort: ProductSortField.relevance,
            resultCount: 12,
            storeNames: {
              '12': locale == 'ar' ? 'ميا كو' : 'MIA CO',
              '9': 'ENARA',
              '7': locale == 'ar' ? 'متجر لولي' : 'loly store',
              '21': locale == 'ar'
                  ? 'المستقبل لمواد البناء'
                  : 'Future Building Materials',
            },
            showHandle: true,
          ),
        ),
      );
      await pumpFor(tester, 700);
    },
    scrolls: 1,
  ),
  // The sort sheet, opened by the sort pill of the listing.
  AuditScene(
    frame: 'B11_filters',
    name: 'sort',
    screen: (locale) => PlpScreen(
      categoryUid: kHomeFurnitureUid,
      title: locale == 'ar' ? 'أثاث منزلي' : 'Home Furniture',
    ),
    setup: _plpSetup,
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tester.tap(find.text(l10n.sortHighestPrice));
      await pumpFor(tester, 700);
    },
  ),
  // Today's Deals' own Filters sheet: Ending soon, 20% or more off, Furniture.
  AuditScene(
    frame: 'B11_filters',
    name: 'deals_filters',
    screen: (_) => const DealsScreen(),
    setup: (_) => _dealsSetup(),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await tester.tap(find.text(l10n.filtersLabel));
      await pumpFor(tester, 700);
      expect(find.byType(DealsFilterSheet), findsOneWidget);
      await tester.tap(find.text(l10n.dealsSortEndingSoon).last);
      await tester.tap(find.text(l10n.filterDiscountOption(20)));
      // The chips count the department's deals as the list stands.
      await tester.tap(find.text('Furniture (3)'));
      await pumpFor(tester, 500);
    },
  ),
];

/// A tap away from the field, as the tests do: the capture is of the page, not
/// of a blinking caret.
Future<void> _unfocus(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await pumpFor(tester, 400);
}

/// The Home of [hubApp]'s layout (Build 2 from `hmAppHome`, Build 1 from the
/// CMS blocks and the category tree), signed in with an open order and recent
/// searches. No search hint of its own in Build 2: the field then says what the
/// frame does.
AuditSetup _homeSetup(String locale, {required bool hubApp}) {
  final countdown = DateTime.now().add(
    const Duration(days: 2, hours: 14, minutes: 32, seconds: 19),
  );
  final cache = FakeLocalCache()
    ..writeString('search_history', homeSearchHistory());
  return AuditSetup(
    account: FakeAccountRepository(orders: [homeOpenOrder()]),
    hubApp: hubApp
        ? HubAppState.available(HmAppConfig(storeCode: locale))
        : const HubAppState.unavailable(),
    overrides: [
      localCacheProvider.overrideWithValue(cache),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hmHomeProvider.overrideWith(
        (ref) async => hubApp
            ? hmHomeFromJson(
                home_fixtures.hmAuditHomeJson(
                  countdown: countdown,
                  arabic: locale == 'ar',
                ),
              )
            : null,
      ),
      homeCmsBlocksProvider.overrideWith((ref) async => build1Blocks),
      homeCategoriesProvider.overrideWith((ref) async => build1Categories),
      categoryThumbnailsProvider.overrideWith(
        (ref, key) async => const <String, String>{},
      ),
      homeCategoryRailProvider.overrideWith((ref, uid) async => build1Rail),
    ],
  );
}

/// The search screens over the Algolia fake [algolia]: no network, the
/// storefront page that carries the key and the multi-query endpoint both
/// answered from memory. With [hubApp] the Hub Market App is there, with its
/// vendors, best sellers and trending searches.
AuditSetup _searchSetup(
  String locale, {
  required FakeAlgoliaBackend algolia,
  required bool hubApp,
  List<Category>? tree,
  FakeLocalCache? cache,
  HmHome? home,
  List<String>? tries,
}) => AuditSetup(
  hubApp: hubApp ? searchHubApp(locale) : const HubAppState.unavailable(),
  overrides: [
    if (cache != null) localCacheProvider.overrideWithValue(cache),
    catalogRepositoryProvider.overrideWithValue(
      FakeCatalogRepository(
        categories: tree ?? (locale == 'ar' ? kSearchTreeAr : kSearchTree),
      ),
    ),
    publicGraphqlClientProvider.overrideWithValue(
      hubApp
          ? searchStoresBackend(locale).client
          : fakeGraphQLClient(),
    ),
    if (tries != null)
      searchTrySuggestionsProvider.overrideWith((ref, query) async => tries),
    if (home != null) hmHomeProvider.overrideWith((ref) async => home),
    algoliaHttpClientProvider.overrideWithValue(algolia.client),
  ],
);

/// The Home Furniture listing: twelve products with a store picked, eighteen
/// without, and the sellers' names for the Store facet.
AuditSetup _plpSetup(String locale) => AuditSetup(
  hubApp: const HubAppState.available(kVendorsHmAppConfig),
  overrides: [
    catalogRepositoryProvider.overrideWithValue(FrameCatalog(locale)),
    publicGraphqlClientProvider.overrideWithValue(
      FakeStoresBackend(storesAnswers(store: locale)).client,
    ),
  ],
);

/// The ranking of Today's Deals and the bundle deals, served from memory.
AuditSetup _dealsSetup() => AuditSetup(
  overrides: [
    publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
    dealsRepositoryProvider.overrideWithValue(FakeDeals()),
  ],
);

/// The brands of Figma 10d and Samsung's products.
AuditSetup _brandsSetup() => AuditSetup(
  overrides: [
    publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
    brandsProvider.overrideWith((ref) async => brandsList),
    catalogRepositoryProvider.overrideWithValue(BrandCatalog()),
  ],
);
