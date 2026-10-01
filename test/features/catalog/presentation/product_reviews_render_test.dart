import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_reviews_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/review_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/pdp_fixtures.dart';

/// Figma 15 (16:1118 / 50:1923): the Reviews screen of the dress with its 27
/// reviews — 15 × 5★, 7 × 4★, 3 × 3★, 1 × 2★, 1 × 1★ — once all of them are in
/// hand, so the bars and the star chips are the frame's. Drawn to
/// build/test_screens/15_reviews_{en,ar}.png; the assertions pin the offsets of
/// the frame (the summary card, the chips, the first review, the footer).

/// The screen opened from a page behind it, as the product page opens it: the
/// app bar then carries its back arrow.
GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, __) => const Scaffold()),
    GoRoute(
      path: '/reviews/:urlKey',
      builder: (_, s) =>
          ProductReviewsScreen(urlKey: s.pathParameters['urlKey']!),
    ),
    GoRoute(
      path: '/review/:sku',
      builder: (_, s) => Text('WRITE ${s.pathParameters['sku']}'),
    ),
  ],
);

Widget _app(
  GoRouter router,
  String locale,
  FakeReviewsRepository repo,
  GlobalKey key,
) {
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      reviewsRepositoryProvider.overrideWithValue(repo),
    ],
    child: RepaintBoundary(
      key: key,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
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

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('15 Reviews, all 27 loaded ($locale)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      final reviews = floralDressReviews(locale: locale);
      final router = _router();
      await tester.pumpWidget(
        _app(
          router,
          locale,
          FakeReviewsRepository(productReviews: reviews, ratingSummary: 86),
          key,
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(AppRoutes.productReviews('floral-dress')));
      await tester.pumpAndSettle();

      // 27 reviews are two pages: scroll to the end for the second, so the
      // bars and the star chips (counted over every review) are offered.
      final list = find.byType(ListView);
      await tester.drag(list, const Offset(0, -5000));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, -5000));
      await tester.pumpAndSettle();
      await tester.drag(list, const Offset(0, 8000));
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNWidgets(5));
      if (locale == 'en') {
        // The frame's offsets under its 56 px app bar (47..103 there): the
        // summary card 16 below it and 136 high, the chips at 166, the
        // first review at 216.
        final barBottom = tester.getRect(find.byType(RuledTopBar)).bottom;
        double below(Finder f) => tester.getTopLeft(f).dy - barBottom;
        expect(tester.getRect(find.byType(RuledTopBar)).height - 56, tester.view.padding.top / tester.view.devicePixelRatio);
        expect(below(find.byType(ReviewsSummaryCard)), 16);
        expect(tester.getSize(find.byType(ReviewsSummaryCard)).height, 136);
        expect(below(find.byKey(const ValueKey('review-filter-all'))), 166);
        expect(below(find.byType(ReviewCard).first), 216);
      }
      await captureScreen(tester, key, '15_reviews_$locale');
      expect(tester.takeException(), isNull);
    });
  }
}
