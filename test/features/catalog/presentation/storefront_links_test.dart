import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/widgets/web_view_screen.dart';
import 'package:hubmarket_app/features/catalog/data/brands_provider.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/presentation/storefront_links.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

/// A page whose only job is to fire [openStorefrontUrl] at [link], so the tap
/// path a home banner CTA takes can be asserted end to end.
class _CtaPage extends ConsumerWidget {
  const _CtaPage(this.link);
  final String link;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => openStorefrontUrl(context, ref, link, title: 'Slide'),
        child: const Text('TAP'),
      ),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String link,
  ({String type, String uid, String? urlKey})? resolved,
  String locale = 'en',
  List<Brand> brands = kSampleBrands,
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(path: AppRoutes.home, builder: (_, __) => _CtaPage(link)),
      GoRoute(
        path: '/category/:uid',
        builder: (_, s) => Text('PLP ${s.pathParameters['uid']}'),
      ),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, s) => Text('PDP ${s.pathParameters['urlKey']}'),
      ),
      GoRoute(
        path: AppRoutes.brand,
        builder: (_, s) => Text('BRAND ${(s.extra! as Brand).optionId}'),
      ),
      GoRoute(path: AppRoutes.brands, builder: (_, __) => const Text('BRANDS')),
      GoRoute(
        path: AppRoutes.webview,
        builder: (_, s) => Text('WEB ${(s.extra! as WebViewArgs).url}'),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      catalogRepositoryProvider.overrideWithValue(
        FakeCatalogRepository(resolved: resolved),
      ),
      brandsProvider.overrideWith((ref) async => brands),
    ],
  );
  addTearDown(container.dispose);
  await container.read(storeControllerProvider.notifier).loadStores();

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.tap(find.text('TAP'));
  await tester.pumpAndSettle();
}

/// Resolved [StoreState] with the sample views loaded, for the pure helper.
Future<StoreState> _loadedState({String locale = 'en'}) async {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(storeControllerProvider.notifier).loadStores();
  return container.read(storeControllerProvider);
}

void main() {
  group('openStorefrontUrl', () {
    // CL042-DEV19/QA01: this is the banner CTA from the ticket. `shopbrand` is
    // a third-party route with no url_rewrite entity, so `urlResolver` returns
    // null. It used to launch externally (Android's app-link filter handed it
    // back to a router with no matching route), then to open the storefront
    // page in the in-app WebView — where `?webview=1` answers HTTP 500 and the
    // shopper got "We couldn't reach the store". It now opens the app's own
    // brand listing, which is what the ticket asked for.
    testWidgets('opens a brand CTA on the native brand listing', (
      tester,
    ) async {
      await _pump(
        tester,
        link: 'https://hub-market.magento2.click/uae-ar/shopbrand/Mancera.html',
      );

      expect(find.text('BRAND 126'), findsOneWidget);
      expect(find.textContaining('WEB '), findsNothing);
    });

    // The live `promoSplitBanners` / `homeBanners` feeds emit a trailing slash
    // after `.html`, which is what QA actually tapped.
    testWidgets('opens a brand CTA carrying the live trailing slash', (
      tester,
    ) async {
      await _pump(
        tester,
        link: 'https://hub-market.magento2.click/uae-en/shopbrand/BathBodyWorks.html/',
      );

      expect(find.text('BRAND 110'), findsOneWidget);
    });

    testWidgets('opens a brand CTA on the Arabic store the same way', (
      tester,
    ) async {
      await _pump(
        tester,
        locale: 'ar',
        link: 'https://hub-market.magento2.click/uae-ar/shopbrand/ANUA.html/',
      );

      expect(find.text('BRAND 158'), findsOneWidget);
    });

    testWidgets('sends the brand index to the Brands directory', (
      tester,
    ) async {
      await _pump(tester, link: 'https://hub-market.magento2.click/uae-en/shopbrand/');

      expect(find.text('BRANDS'), findsOneWidget);
    });

    // The feed being empty (offline, or the brand deleted) must not dead-end:
    // fall back to the page itself, now WITHOUT `webview=1`.
    testWidgets('falls back to the in-app WebView for an unknown brand', (
      tester,
    ) async {
      await _pump(
        tester,
        link: 'https://hub-market.magento2.click/uae-en/shopbrand/Nowhere.html',
        brands: const <Brand>[],
      );

      expect(
        find.text('WEB https://hub-market.magento2.click/uae-en/shopbrand/Nowhere.html'),
        findsOneWidget,
      );
    });

    testWidgets('opens a CMS page in the in-app WebView without webview=1', (
      tester,
    ) async {
      await _pump(tester, link: 'https://hub-market.magento2.click/uae-en/about-us/');

      expect(
        find.text('WEB https://hub-market.magento2.click/uae-en/about-us/'),
        findsOneWidget,
      );
    });

    testWidgets('maps a category-id URL straight to the PLP', (tester) async {
      await _pump(
        tester,
        link: 'https://hub-market.magento2.click/uae-en/catalog/category/view/id/5/',
      );

      expect(find.text('PLP NQ=='), findsOneWidget);
    });

    testWidgets('sends a resolved PRODUCT to the PDP', (tester) async {
      await _pump(
        tester,
        link: 'https://hub-market.magento2.click/uae-en/fragrance/coco.html',
        resolved: (type: 'PRODUCT', uid: '', urlKey: 'coco'),
      );

      expect(find.text('PDP coco'), findsOneWidget);
    });

    testWidgets('sends a resolved CATEGORY to the PLP', (tester) async {
      await _pump(
        tester,
        link: 'https://hub-market.magento2.click/uae-en/fragrance.html',
        resolved: (type: 'CATEGORY', uid: 'cat-frag', urlKey: 'fragrance'),
      );

      expect(find.text('PLP cat-frag'), findsOneWidget);
    });

    testWidgets('leaves a foreign host to the platform, navigating nowhere', (
      tester,
    ) async {
      await _pump(tester, link: 'https://example.com/campaign');

      expect(find.text('TAP'), findsOneWidget);
      expect(find.textContaining('WEB '), findsNothing);
    });

    testWidgets('resolves a store-relative brand CTA against the active view', (
      tester,
    ) async {
      await _pump(tester, link: 'shopbrand/Mancera.html');

      expect(find.text('BRAND 126'), findsOneWidget);
    });
  });

  group('brandFromStorefrontUrl', () {
    test('matches the url_key segment', () {
      expect(
        brandFromStorefrontUrl(
          kSampleBrands,
          'https://hub-market.magento2.click/uae-en/shopbrand/Mancera.html',
        )?.optionId,
        126,
      );
    });

    test('tolerates the trailing slash the live feed emits', () {
      expect(
        brandFromStorefrontUrl(
          kSampleBrands,
          'https://hub-market.magento2.click/uae-en/shopbrand/ANUA.html/',
        )?.optionId,
        158,
      );
    });

    test('matches case-insensitively', () {
      expect(
        brandFromStorefrontUrl(kSampleBrands, 'shopbrand/anua.html')?.optionId,
        158,
      );
    });

    test('matches with .html absent', () {
      expect(
        brandFromStorefrontUrl(kSampleBrands, 'shopbrand/Mancera')?.optionId,
        126,
      );
    });

    test('works under the Arabic store segment', () {
      expect(
        brandFromStorefrontUrl(
          kSampleBrands,
          'https://hub-market.magento2.click/uae-ar/shopbrand/BathBodyWorks.html',
        )?.optionId,
        110,
      );
    });

    // Admin can key a banner by the display name where the feed carries the
    // punctuation-free key.
    test('folds punctuation so a display-name key still matches', () {
      expect(
        brandFromStorefrontUrl(
          kSampleBrands,
          'shopbrand/Bath-Body-Works.html',
        )?.optionId,
        110,
      );
    });

    test('is null for an unknown brand', () {
      expect(
        brandFromStorefrontUrl(kSampleBrands, 'shopbrand/Nowhere.html'),
        isNull,
      );
    });

    test('is null for the brand index and for a non-brand URL', () {
      expect(brandFromStorefrontUrl(kSampleBrands, 'shopbrand/'), isNull);
      expect(brandFromStorefrontUrl(kSampleBrands, 'fragrance.html'), isNull);
    });

    test('isBrandIndexUrl only for the index', () {
      expect(isBrandIndexUrl('https://hub-market.magento2.click/uae-en/shopbrand/'), isTrue);
      expect(isBrandIndexUrl('https://hub-market.magento2.click/uae-en/shopbrand'), isTrue);
      expect(isBrandIndexUrl('shopbrand/Mancera.html'), isFalse);
      expect(isBrandIndexUrl('fragrance.html'), isFalse);
    });
  });

  group('inAppStorefrontUrl', () {
    // CL042-DEV19/QA01: `webview=1` answers HTTP 500 on brand pages, so the app
    // no longer sends it anywhere.
    test('keeps an existing query and adds nothing', () async {
      expect(
        inAppStorefrontUrl(
          await _loadedState(),
          'https://hub-market.magento2.click/p.html?utm=x',
        ),
        'https://hub-market.magento2.click/p.html?utm=x',
      );
    });

    test('upgrades http to https', () async {
      expect(
        inAppStorefrontUrl(await _loadedState(), 'http://hub-market.magento2.click/p.html'),
        'https://hub-market.magento2.click/p.html',
      );
    });

    test('resolves a relative path against the active view', () async {
      expect(
        inAppStorefrontUrl(await _loadedState(locale: 'ar'), 'shopbrand/'),
        'https://hub-market.magento2.click/uae-ar/shopbrand/',
      );
    });

    test('does not double a path that already carries the store segment', () async {
      expect(
        inAppStorefrontUrl(await _loadedState(), '/uae-en/shopbrand/'),
        'https://hub-market.magento2.click/uae-en/shopbrand/',
      );
    });

    test('is null when store config has not loaded', () {
      const empty = StoreState(
        activeLocale: 'en',
        localeToCode: <String, String>{},
        defaultLocale: 'en',
        currency: 'AED',
      );
      expect(inAppStorefrontUrl(empty, 'shopbrand/'), isNull);
    });
  });
}
