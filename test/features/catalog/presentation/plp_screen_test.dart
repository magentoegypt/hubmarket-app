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
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';

Widget _harness(String locale) {
  final router = GoRouter(
    initialLocation: '/category/cat-fragrance',
    routes: [
      GoRoute(
        path: '/category/:uid',
        builder: (_, state) => PlpScreen(
          categoryUid: state.pathParameters['uid']!,
          title: 'Fragrance',
        ),
      ),
      GoRoute(path: '/product/:urlKey', builder: (_, __) => const Scaffold()),
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
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      // Footer fires the store-contact config query — keep it offline.
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      // The listing asks whether stores are available (vendor facets).
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

void main() {
  testWidgets('PLP renders products with separate Sort + Filter controls', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    expect(find.text('Fragrance'), findsWidgets);
    // Two distinct controls under the app bar (QA 86d3m97au, Figma 10): the
    // Filters chip, and the sort with the listing's own order named (the
    // website's default: highest price first).
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Highest price'), findsOneWidget);
    expect(find.text('2 products'), findsOneWidget);
    expect(find.text('Coco Mademoiselle EDP'), findsWidgets);
    // Search and Cart sit in the app bar.
    expect(find.byTooltip('Search for products…'), findsOneWidget);
    expect(find.byTooltip('Cart'), findsOneWidget);
  });

  testWidgets('filter sheet shows the facets, the sort and "Show N results"', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    // The sheet repeats the listing's sort as "Sort by" chips (Figma 11);
    // Newest first waits for the backend field.
    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Relevance'), findsWidgets);
    expect(find.text('Lowest price'), findsOneWidget);
    expect(find.text('Newest first'), findsNothing);
    // Brand facet from aggregations, with selectable options (as chips).
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Chanel'), findsOneWidget);
    expect(find.text('Dior'), findsOneWidget);
    // No Discount / Rating thresholds: Hub Market has no filterable attribute
    // for either (kDiscountFilterSupported / kRatingFilterSupported).
    expect(find.text('Discount'), findsNothing);
    expect(find.text('50% or more'), findsNothing);
    expect(find.text('Customer rating'), findsNothing);
    // Reset in the header, one button under the sheet: the count of results.
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Clear All'), findsNothing);
    expect(find.text('Show 2 results'), findsOneWidget);
  });

  testWidgets('sort sheet lists the sorts the backend can do; Newest first waits', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    // The sort is the line's action, named after the order in force.
    await tester.tap(find.text('Highest price'));
    await tester.pumpAndSettle();

    expect(find.text('Relevance'), findsOneWidget);
    expect(find.text('Lowest price'), findsOneWidget);
    expect(find.text('Highest price'), findsWidgets);
    expect(find.text('Name: A–Z'), findsOneWidget);
    // Newest first present but gated until the backend adds the sort field.
    expect(find.text('Newest first'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);

    // Picking one sorts the listing by it, and the line says so.
    await tester.tap(find.text('Lowest price'));
    await tester.pumpAndSettle();
    expect(find.text('Lowest price'), findsOneWidget);
    expect(find.text('Highest price'), findsNothing);
  });
}
