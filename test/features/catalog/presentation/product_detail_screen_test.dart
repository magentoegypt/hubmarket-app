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
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/checkout/payments/tabby_promo.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

Widget _harness(String locale) {
  final router = GoRouter(
    initialLocation: '/product/coco-mademoiselle',
    routes: [
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) =>
            ProductDetailScreen(urlKey: state.pathParameters['urlKey']!),
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
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      // Keep the PDP test network-free; the Tabby promo is covered separately.
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      tabbyConfigProvider.overrideWith((ref) => null),
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
  testWidgets('renders product detail and updates price on variant select', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    expect(find.text('Coco Mademoiselle EDP'), findsWidgets);
    expect(find.text('AED 199.00'), findsWidgets);

    await tester.tap(find.text('100ml'));
    await tester.pumpAndSettle();

    expect(find.text('AED 299.00'), findsWidgets);
  });

  testWidgets('reviews tab shows the empty state (store has zero reviews)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Reviews'));
    await tester.pumpAndSettle();

    expect(find.text('No reviews yet'), findsOneWidget);
  });
}
