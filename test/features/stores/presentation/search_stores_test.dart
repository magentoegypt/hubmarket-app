import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/algolia/algolia_settings_repository.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/stores/presentation/widgets/search_vendor_widgets.dart';
import 'package:hubmarket_app/features/stores/presentation/widgets/store_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/algolia_fakes.dart';
import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/search_fixtures.dart';
import '../../../support/store_fixtures.dart';

/// The seller API for search: [named] answers a name search; the directory
/// (no name) is every seller; best sellers for S2.
FakeStoresBackend _stores({List<Map<String, dynamic>> named = const []}) =>
    FakeStoresBackend(
      (r) => switch (r.operation) {
        'HmStores' when r.variables['name'] != null => storesData(named),
        'HmStores' => storesData(sampleStoreCards()),
        'HmBestSellers' => bestSellersData(),
        _ => Exception('offline (test): ${r.operation}'),
      },
    );

Widget _harness({
  required FakeAlgoliaBackend algolia,
  required FakeStoresBackend stores,
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  String? initialQuery,
}) {
  Widget stub(String text) => Scaffold(appBar: AppBar(), body: Text(text));
  final router = GoRouter(
    initialLocation: '/search',
    routes: [
      GoRoute(
        path: '/search',
        builder: (_, __) => SearchScreen(initialQuery: initialQuery),
      ),
      GoRoute(
        path: '/store/:code',
        builder: (_, state) => stub('STORE ${state.pathParameters['code']}'),
      ),
      GoRoute(path: '/stores', builder: (_, __) => stub('STORES')),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) => stub('PDP ${state.pathParameters['urlKey']}'),
      ),
      GoRoute(
        path: '/category/:uid',
        builder: (_, state) => stub('PLP ${state.pathParameters['uid']}'),
      ),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
      ])
        GoRoute(path: p, builder: (_, __) => stub(p)),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(categories: kSearchTree),
      ),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      publicGraphqlClientProvider.overrideWithValue(stores.client),
      algoliaHttpClientProvider.overrideWithValue(algolia.client),
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
  );
}

Future<void> _phone(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  group('results (Figma 09c) with the seller API', () {
    testWidgets('a Vendors tab, and the seller of the matches as a card', (
      tester,
    ) async {
      await _phone(tester);
      final stores = _stores();
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(answer: sofaAnswers()),
          stores: stores,
          initialQuery: 'sofa',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Products (12)'), findsOneWidget);
      expect(find.text('Vendors (1)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
      // Algolia's seller facet counts MIA CO's 8 of the 12 matches.
      final card = find.byType(SearchVendorCard);
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('MIA CO')),
        findsOneWidget,
      );
      expect(find.text('8 matching products'), findsOneWidget);
      // The name search asked, and the directory named the facet's seller.
      expect(
        stores.of('HmStores').map((r) => r.variables['name']),
        containsAll(<String?>['sofa', null]),
      );

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('STORE MIA'), findsOneWidget);
    });

    testWidgets('the Vendors tab lists the sellers; one opens its store', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(answer: sofaAnswers()),
          stores: _stores(
            named: [
              storeCardJson(
                code: 'sofa_world',
                id: 40,
                name: 'Sofa World',
                products: 12,
              ),
            ],
          ),
          initialQuery: 'sofa',
        ),
      );
      await tester.pumpAndSettle();

      // A store named like the query leads; then the seller of the matches.
      expect(find.text('Vendors (2)'), findsOneWidget);
      await tester.tap(find.text('Vendors (2)'));
      await tester.pumpAndSettle();
      final tiles = find.byType(StoreListTile);
      expect(tiles, findsNWidgets(2));
      expect(
        find.descendant(of: tiles.first, matching: find.text('Sofa World')),
        findsOneWidget,
      );
      expect(find.text('12 products'), findsOneWidget);
      expect(find.text('8 matching products'), findsWidgets);

      await tester.tap(find.text('Sofa World').last);
      await tester.pumpAndSettle();
      expect(find.text('STORE sofa_world'), findsOneWidget);
    });

    testWidgets('no product, but a store by that name: opens on Vendors', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(
            answer: sofaAnswers(products: false, suggestions: false),
          ),
          stores: _stores(named: [miaCard()]),
          initialQuery: 'mia',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Products (0)'), findsOneWidget);
      expect(find.text('Vendors (1)'), findsOneWidget);
      expect(find.byType(StoreListTile), findsOneWidget);
      expect(find.text('38 products'), findsOneWidget);
      expect(find.text('Browse stores'), findsNothing);
    });

    testWidgets('a seller API failure only leaves the vendors out', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(answer: sofaAnswers()),
          stores: FakeStoresBackend((_) => Exception('offline (test)')),
          initialQuery: 'sofa',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Products (12)'), findsOneWidget);
      expect(find.text('Vendors (0)'), findsOneWidget);
      expect(find.byType(SearchVendorCard), findsNothing);
      await tester.tap(find.text('Vendors (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No stores match “\u2068sofa\u2069”.'), findsOneWidget);
    });
  });

  group('no results (Figma S2) with the seller API', () {
    testWidgets('Browse stores and the best sellers as Popular right now', (
      tester,
    ) async {
      await _phone(tester);
      final stores = _stores();
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(
            answer: sofaAnswers(products: false, suggestions: false),
          ),
          stores: stores,
        ),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'sofa bed velvet green');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        find.text('No results for “\u2068sofa bed velvet green\u2069”'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Check the spelling or use fewer words. You can also browse our stores.',
        ),
        findsOneWidget,
      );
      expect(find.text('Browse stores'), findsOneWidget);
      expect(find.text('Popular right now'), findsOneWidget);
      expect(find.text('Joust Duffle Bag'), findsOneWidget);
      expect(stores.of('HmBestSellers').first.variables['pageSize'], 10);

      await tester.tap(find.text('Browse stores'));
      await tester.pumpAndSettle();
      expect(find.text('STORES'), findsOneWidget);
    });
  });

  group('fallback: without the Hub Market App', () {
    testWidgets('results keep their two tabs; nothing asks the seller API', (
      tester,
    ) async {
      await _phone(tester);
      final stores = _stores();
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(answer: sofaAnswers()),
          stores: stores,
          hubApp: const HubAppState.unavailable(),
          initialQuery: 'sofa',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Products (12)'), findsOneWidget);
      expect(find.text('Categories (3)'), findsOneWidget);
      expect(find.textContaining('Vendors'), findsNothing);
      expect(find.byType(SearchVendorCard), findsNothing);
      expect(stores.requests, isEmpty);
    });

    testWidgets('S2 keeps its own layout', (tester) async {
      await _phone(tester);
      final stores = _stores();
      await tester.pumpWidget(
        _harness(
          algolia: FakeAlgoliaBackend(
            answer: sofaAnswers(products: false, suggestions: false),
          ),
          stores: stores,
          hubApp: const HubAppState.unknown(),
          initialQuery: 'sofa bed velvet green',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Check the spelling or use fewer words.'),
        findsOneWidget,
      );
      expect(find.text('Browse stores'), findsNothing);
      expect(find.text('Popular right now'), findsNothing);
      expect(stores.requests, isEmpty);
    });
  });
}
