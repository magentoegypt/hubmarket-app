import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/plp_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

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
    // Two distinct controls in the header (QA 86d3m97au).
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Filters'), findsOneWidget);
    expect(find.text('Coco Mademoiselle EDP'), findsWidgets);
  });

  testWidgets('filter sheet shows facets, Discount + Rating, and footer — no Sort', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    // Sort moved OUT of the filter sheet into its own control.
    expect(find.text('Sort By'), findsNothing);
    // Brand facet from aggregations, with selectable options.
    expect(find.text('Brand'), findsOneWidget);
    expect(find.text('Chanel'), findsOneWidget);
    expect(find.text('Dior'), findsOneWidget);
    // Website's Discount + Rating threshold sections.
    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('50% or more'), findsOneWidget);
    expect(find.text('Rating'), findsOneWidget);
    expect(find.text('& above'), findsWidgets);
    // Two-button footer + header reset.
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Clear All'), findsOneWidget);
    expect(find.text('Apply Filters'), findsOneWidget);
  });

  testWidgets('sort sheet lists all website options; Newest First disabled', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sort'));
    await tester.pumpAndSettle();

    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('Price: Low to High'), findsOneWidget);
    expect(find.text('Price: High to Low'), findsOneWidget);
    expect(find.text('Name: A–Z'), findsOneWidget);
    // Newest First present but gated until the backend adds the sort field.
    expect(find.text('Newest First'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });
}
