import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/not_found_state.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_reviews_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';

/// A product the store does not have (a stale or rewritten link): both its
/// pages answer with Figma S7, "This page isn't available".
class _NoSuchProduct extends FakeCatalogRepository {
  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async => null;
}

Future<void> _pump(
  WidgetTester tester, {
  required String location,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, s) =>
            ProductDetailScreen(urlKey: s.pathParameters['urlKey']!),
      ),
      GoRoute(
        path: '/reviews/:urlKey',
        builder: (_, s) =>
            ProductReviewsScreen(urlKey: s.pathParameters['urlKey']!),
      ),
      for (final p in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.search,
      ])
        GoRoute(path: p, builder: (_, __) => Text('ROUTE $p')),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        catalogRepositoryProvider.overrideWithValue(_NoSuchProduct()),
        reviewsRepositoryProvider.overrideWithValue(
          FakeReviewsRepository(productExists: false),
        ),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        hubAppOverride(const HubAppState.unavailable()),
      ],
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
  await tester.pumpAndSettle();
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  for (final (name, location) in [
    ('the product page', '/product/gone'),
    ('the product reviews', '/reviews/gone'),
  ]) {
    testWidgets('$name for a product that does not exist is the S7 page', (
      tester,
    ) async {
      await _pump(tester, location: location);

      expect(find.byType(NotFoundState), findsOneWidget);
      expect(find.text(en.notFoundTitle), findsOneWidget);
      expect(find.text(en.notFoundBody), findsOneWidget);
      expect(find.text(en.notFoundSearch), findsOneWidget);
      expect(find.text(en.notFoundHome), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('in Arabic it says it in the frame\'s words', (tester) async {
    await _pump(tester, location: '/product/gone', locale: 'ar');

    expect(find.text(ar.notFoundTitle), findsOneWidget);
    expect(find.text('هذه الصفحة غير متاحة'), findsOneWidget);
    expect(find.text('ابحث في هب ماركت'), findsOneWidget);
    expect(find.text('العودة للرئيسية'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Go to Home" leaves the dead page for Home', (tester) async {
    await _pump(tester, location: '/product/gone');

    await tester.tap(find.text(en.notFoundHome));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE ${AppRoutes.home}'), findsOneWidget);
  });
}
