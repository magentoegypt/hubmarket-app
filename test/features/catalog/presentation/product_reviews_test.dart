import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_subject.dart';
import 'package:hubmarket_app/features/catalog/presentation/reviews_controllers.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_reviews_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/review_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

/// 27 reviews, as on the Figma frame: 15×5★, 7×4★, 3×3★, 1×2★, 1×1★.
final _figmaReviews = <ProductReview>[
  for (var i = 0; i < 15; i++) sampleReview(5, nickname: 'Five $i'),
  for (var i = 0; i < 7; i++) sampleReview(4, nickname: 'Four $i'),
  for (var i = 0; i < 3; i++) sampleReview(3, nickname: 'Three $i'),
  sampleReview(2, nickname: 'Two'),
  sampleReview(1, nickname: 'One'),
];

ProviderContainer _container(FakeReviewsRepository repo) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      reviewsRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProductReviewsState> _settled(ProviderContainer c, String key) async {
  // Keep the autoDispose family alive while the test reads it.
  c.listen(productReviewsControllerProvider(key), (_, __) {});
  var state = c.read(productReviewsControllerProvider(key));
  while (state.isLoading || state.isLoadingMore) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    state = c.read(productReviewsControllerProvider(key));
  }
  return state;
}

void main() {
  group('ProductReviewsController paging', () {
    test('loads page 1, then appends page 2 on loadMore', () async {
      final repo = FakeReviewsRepository(productReviews: _figmaReviews);
      final c = _container(repo);

      var state = await _settled(c, 'dress');
      expect(state.reviews, hasLength(20));
      expect(state.product!.reviewCount, 27);
      expect(state.hasMore, isTrue);

      await c.read(productReviewsControllerProvider('dress').notifier).loadMore();
      state = await _settled(c, 'dress');
      expect(state.reviews, hasLength(27));
      expect(state.hasMore, isFalse);
      expect(repo.productPagesRequested, [1, 2]);

      // No page 3 is requested past the last one.
      await c.read(productReviewsControllerProvider('dress').notifier).loadMore();
      expect(repo.productPagesRequested, [1, 2]);
    });

    test('bars are counted only once every review is loaded', () async {
      final c = _container(FakeReviewsRepository(productReviews: _figmaReviews));

      var state = await _settled(c, 'dress');
      // 20 of 27: a partial page says nothing about the rest — no bars.
      expect(state.histogram, isEmpty);

      await c.read(productReviewsControllerProvider('dress').notifier).loadMore();
      state = await _settled(c, 'dress');
      expect(
        [for (final b in state.histogram) (b.stars, b.count)],
        [(5, 15), (4, 7), (3, 3), (2, 1), (1, 1)],
      );
    });

    test('a review_count above what the list returns keeps bars off', () async {
      final c = _container(
        FakeReviewsRepository(productReviews: _figmaReviews.take(5).toList(), reviewCount: 9),
      );
      final state = await _settled(c, 'dress');
      expect(state.hasMore, isFalse);
      expect(state.histogram, isEmpty);
    });

    test('an unknown product is reported as not found', () async {
      final c = _container(FakeReviewsRepository(productExists: false));
      final state = await _settled(c, 'gone');
      expect(state.notFound, isTrue);
    });
  });

  group('ProductReviewsScreen', () {
    Future<void> pump(
      WidgetTester tester,
      FakeReviewsRepository repo, {
      String locale = 'en',
    }) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: AppRoutes.productReviews('dress'),
        routes: [
          GoRoute(
            path: '/reviews/:urlKey',
            builder: (_, s) =>
                ProductReviewsScreen(urlKey: s.pathParameters['urlKey']!),
          ),
          GoRoute(
            path: '/review/:sku',
            builder: (_, s) => Text(
              'WRITE ${s.pathParameters['sku']} '
              '${(s.extra as ReviewSubject?)?.name}',
            ),
          ),
          for (final p in ['/home', '/categories', '/cart', '/wishlist', '/account'])
            GoRoute(path: p, builder: (_, __) => const Scaffold()),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            localCacheProvider.overrideWithValue(FakeLocalCache()),
            localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
            secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
            reviewsRepositoryProvider.overrideWithValue(repo),
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
    }

    final en = lookupAppLocalizations(const Locale('en'));

    testWidgets('a complete set shows bars and star filters', (tester) async {
      await pump(
        tester,
        FakeReviewsRepository(
          productReviews: [sampleReview(5), sampleReview(5), sampleReview(3)],
        ),
      );
      expect(find.text(en.reviewsScreenTitle), findsOneWidget);
      expect(find.text(en.reviewsCount(3)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(5));
      expect(find.byKey(const ValueKey('review-filter-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('review-filter-3')), findsOneWidget);
      // No 4★ reviews, no 4★ chip.
      expect(find.byKey(const ValueKey('review-filter-4')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('review-filter-3')));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewStars), findsNWidgets(2)); // summary + 1 card
    });

    testWidgets('a partial set shows the average without bars', (tester) async {
      await pump(tester, FakeReviewsRepository(productReviews: _figmaReviews));
      expect(find.text(en.reviewsCount(27)), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('review-filter-5')), findsNothing);
    });

    testWidgets('Write a review opens the review form, with the product', (
      tester,
    ) async {
      await pump(tester, FakeReviewsRepository(productReviews: [sampleReview(4)]));
      await tester.tap(find.text(en.reviewsWrite));
      await tester.pumpAndSettle();
      expect(find.text('WRITE SKU-dress Product dress'), findsOneWidget);
    });

    testWidgets('has no tab bar: its footer is the Write a review button', (
      tester,
    ) async {
      await pump(tester, FakeReviewsRepository(productReviews: [sampleReview(4)]));
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(find.text(en.navCart), findsNothing);
      expect(find.text(en.reviewsWrite), findsOneWidget);
    });

    testWidgets('renders right-to-left in Arabic', (tester) async {
      await pump(
        tester,
        FakeReviewsRepository(productReviews: [sampleReview(4)]),
        locale: 'ar',
      );
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(find.text(ar.reviewsScreenTitle), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text('Nour A.'))),
        TextDirection.rtl,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
