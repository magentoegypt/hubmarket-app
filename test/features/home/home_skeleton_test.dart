import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/hubapp/hubapp_providers.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/shimmer.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_skeletons.dart';
import 'package:hubmarket_app/features/home/presentation/hub_home_screen.dart';
import 'package:hubmarket_app/features/home/presentation/widgets/home_skeleton.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';

/// A probe that is still out: the Home has nothing to draw yet.
class _PendingProbe extends HubAppController {
  @override
  Future<HubAppState> build() => Completer<HubAppState>().future;
}

Widget _harness(String locale, GlobalKey boundary) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HubHomeScreen()),
      for (final p in [
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
        '/search',
        '/notifications',
        '/addresses',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppProvider.overrideWith(_PendingProbe.new),
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

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('S4: the Home waiting for its content shows the frame\'s '
        'skeleton ($locale)', (tester) => withRealShadows(() async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.reset);
      // The frame is the resting skeleton: no sweep over it.
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final key = GlobalKey();
      await tester.pumpWidget(_harness(locale, key));
      await tester.pump(const Duration(milliseconds: 400));
      await captureScreen(tester, key, 'S4_home_loading_$locale');

      expect(find.byType(HomeSkeleton), findsOneWidget);
      // Hero, five circles and their captions, the title, two cards of five.
      expect(find.byType(SkeletonBox), findsNWidgets(1 + 10 + 1 + 2 * 5));
      expect(find.byType(ProductCardSkeletonShape), findsNWidgets(2));
      // One shimmer runs over the whole page.
      expect(
        find.descendant(
          of: find.byType(HomeSkeleton),
          matching: find.byType(Shimmer),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }));
  }

  testWidgets('the skeleton blocks are the frame\'s fill and sizes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: HomeSkeleton())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    final boxes = find.byType(SkeletonBox);
    final hero = tester.getRect(boxes.first);
    expect(hero.width, 358);
    expect(hero.height, 168);
    // Every block is drawn in bg/subtle.
    for (final box in tester.widgetList<SkeletonBox>(boxes)) {
      expect(box.color, AppColors.surfaceSubtle);
    }
    // Two cards 171 px wide, 253 high (image 171 and four bars 8 apart).
    final cards = find.byType(ProductCardSkeletonShape);
    for (var i = 0; i < 2; i++) {
      final size = tester.getSize(cards.at(i));
      expect(size.width, 171);
      expect(size.height, 253);
    }
    expect(tester.takeException(), isNull);
  });
}
