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
import 'package:hubmarket_app/features/catalog/data/hero_slides_provider.dart';
import 'package:hubmarket_app/features/catalog/data/home_sections_provider.dart';
import 'package:hubmarket_app/features/catalog/domain/hero_slide.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/home_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

Widget _harness(String locale, {List<HeroSlide>? heroSlides}) {
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/category/:uid',
        builder: (_, s) =>
            Scaffold(body: Text('PLP ${s.pathParameters['uid']}')),
      ),
      GoRoute(path: '/product/:urlKey', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/search', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/categories', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/cart', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/wishlist', builder: (_, __) => const Scaffold()),
      GoRoute(path: '/account', builder: (_, __) => const Scaffold()),
    ],
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      catalogRepositoryProvider.overrideWithValue(FakeCatalogRepository()),
      // "Shop by Category" is its own backend feed (not the menu tree the
      // catalog repository serves), so it needs its own override — offline it
      // would return empty and the section would correctly hide itself.
      shopByCategoriesProvider.overrideWith(
        (_) async => kSampleShopByCategories,
      ),
      // Home fires storeConfig/hero/brands/footer queries — keep them offline
      // so they degrade to fallbacks without leaving retry-backoff timers.
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      if (heroSlides != null)
        heroSlidesProvider.overrideWith((_) async => heroSlides),
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
  // A tall surface so the lazy body list builds all sections in the test.
  Future<void> pumpHome(
    WidgetTester tester,
    String locale, {
    List<HeroSlide>? heroSlides,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(locale, heroSlides: heroSlides));
    await tester.pumpAndSettle();
  }

  testWidgets('renders categories + product sections in English / LTR', (
    tester,
  ) async {
    await pumpHome(tester, 'en');

    // Section headers are uppercased (Figma).
    expect(find.text('SHOP BY CATEGORY'), findsWidgets);
    // New Arrivals replaced the old "Featured" section (Figma).
    expect(find.text('NEW ARRIVALS'), findsWidgets);
    // A curated "Shop by Category" tile.
    expect(find.text('Fragrance'), findsWidgets);
    expect(find.text('Coco Mademoiselle EDP'), findsWidgets);

    final direction = Directionality.of(
      tester.element(find.text('Coco Mademoiselle EDP').first),
    );
    expect(direction, TextDirection.ltr);
  });

  testWidgets('renders in Arabic / RTL', (tester) async {
    await pumpHome(tester, 'ar');

    expect(find.text('تسوّق حسب الفئة'), findsWidgets);

    final direction = Directionality.of(
      tester.element(find.text('Fragrance').first),
    );
    expect(direction, TextDirection.rtl);
  });

  // CL042-DEV19: the hero's only tap target was the CTA button, and the button
  // only rendered when the merchant had set `cta_label` — so a slide published
  // with a URL but no label was completely dead to touch.
  group('hero slide without a cta_label', () {
    const slide = HeroSlide(
      slideId: 1,
      position: 0,
      eyebrow: '',
      title: 'Matte Perfection',
      description: '',
      ctaLabel: '',
      ctaUrl: 'https://hub-market.magento2.click/uae-en/catalog/category/view/id/5/',
      imageUrl: '',
      videoUrl: '',
    );

    testWidgets('still falls back to a visible CTA', (tester) async {
      await pumpHome(tester, 'en', heroSlides: const [slide]);

      expect(find.text('Shop Now'), findsWidgets);
    });

    testWidgets('routes when the card itself is tapped', (tester) async {
      await pumpHome(tester, 'en', heroSlides: const [slide]);

      // Tap the slide's headline — anywhere on the card, not the button.
      await tester.tap(find.text('Matte Perfection').first);
      await tester.pumpAndSettle();

      // id 5 -> base64("5") == "NQ==".
      expect(find.text('PLP NQ=='), findsOneWidget);
    });
  });
}
