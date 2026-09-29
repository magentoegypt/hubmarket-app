import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/presentation/screens/my_reviews_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/catalog/presentation/reviews_controllers.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

CustomerReview _mine(String product, int stars) => CustomerReview(
  review: sampleReview(stars),
  productName: product,
  productSku: 'SKU-$product',
  productUrlKey: product.toLowerCase().replaceAll(' ', '-'),
);

final _three = [
  _mine('Floral Print Dress', 4),
  _mine('Corner Sofa Bed', 5),
  _mine('Full Cream Milk', 4),
];

Future<FakeReviewsRepository> _pump(
  WidgetTester tester, {
  List<CustomerReview>? reviews,
  String? token = 'persisted',
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeReviewsRepository(customerReviews: reviews ?? _three);
  final router = GoRouter(
    initialLocation: AppRoutes.myReviews,
    routes: [
      GoRoute(
        path: AppRoutes.myReviews,
        builder: (_, __) => const MyReviewsScreen(),
      ),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, s) => Text('PDP ${s.pathParameters['urlKey']}'),
      ),
      for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account', '/signin'])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore(token)),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        reviewsRepositoryProvider.overrideWithValue(repo),
        // The signed-in shell (cart / wishlist badges) stays offline.
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
        wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
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
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  testWidgets('lists the customer\'s reviews with their products', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text(en.myReviewsTitle), findsOneWidget);
    expect(find.text('Floral Print Dress'), findsOneWidget);
    expect(find.text('Corner Sofa Bed'), findsOneWidget);
    // Every page is in, so the count is exact.
    expect(
      find.text('${en.myReviewsCount(3)} · ${en.myReviewsApprovalNote}'),
      findsOneWidget,
    );
    // No invented moderation badge: core reviews carry no status.
    expect(find.text('PENDING'), findsNothing);
    expect(find.text('PUBLISHED'), findsNothing);
  });

  testWidgets('a card opens its product', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Corner Sofa Bed'));
    await tester.pumpAndSettle();
    expect(find.text('PDP corner-sofa-bed'), findsOneWidget);
  });

  testWidgets('pages past 20 reviews, count unknown until the end', (
    tester,
  ) async {
    final many = [for (var i = 0; i < 25; i++) _mine('Product $i', 4)];
    final repo = await _pump(tester, reviews: many);
    expect(find.text(en.myReviewsApprovalNote), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MyReviewsScreen)),
    );
    await container.read(myReviewsControllerProvider.notifier).loadMore();
    await tester.pumpAndSettle();
    expect(repo.customerPagesRequested, [1, 2]);
    expect(container.read(myReviewsControllerProvider).items, hasLength(25));
    expect(container.read(myReviewsControllerProvider).count, 25);
  });

  testWidgets('empty list explains where reviews come from', (tester) async {
    await _pump(tester, reviews: const []);
    expect(find.text(en.myReviewsEmptyBody), findsOneWidget);
  });

  testWidgets('a guest is asked to sign in, nothing is fetched', (
    tester,
  ) async {
    final repo = await _pump(tester, token: null);
    expect(find.text(en.myReviewsSignIn), findsOneWidget);
    expect(repo.customerPagesRequested, isEmpty);
  });

  testWidgets('renders right-to-left in Arabic', (tester) async {
    await _pump(tester, locale: 'ar');
    final ar = lookupAppLocalizations(const Locale('ar'));
    expect(find.text(ar.myReviewsTitle), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('Corner Sofa Bed'))),
      TextDirection.rtl,
    );
  });
}
