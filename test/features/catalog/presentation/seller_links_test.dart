import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/deep_link_resolver_screen.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/widgets/web_view_screen.dart';
import 'package:hubmarket_app/features/catalog/data/brands_provider.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/storefront_links.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/hubapp_fakes.dart';

const _seller = 'https://hub-market.magento2.click/uae-en/shop/loly/';

/// A page that fires [openStorefrontUrl] at [link], as a CMS promo does.
class _CtaPage extends ConsumerWidget {
  const _CtaPage(this.link);
  final String link;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: TextButton(
      onPressed: () => openStorefrontUrl(context, ref, link),
      child: const Text('TAP'),
    ),
  );
}

/// [link] handled the way [tapped] says — a tap on an in-app link, or an App
/// Link the route table can't match — with HubApp as [hubApp].
Future<({GoRouter router, FakeCatalogRepository catalog})> _open(
  WidgetTester tester, {
  required String link,
  required HubAppState hubApp,
  bool tapped = true,
}) async {
  final catalog = FakeCatalogRepository();
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    errorBuilder: (_, state) => DeepLinkResolverScreen(uri: state.uri),
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => tapped ? _CtaPage(link) : const Text('HOME'),
      ),
      GoRoute(
        path: '/store/:code',
        builder: (_, s) => Text('STORE ${s.pathParameters['code']}'),
      ),
      GoRoute(path: AppRoutes.stores, builder: (_, __) => const Text('STORES')),
      GoRoute(
        path: AppRoutes.webview,
        builder: (_, s) => Text('WEB ${(s.extra! as WebViewArgs).url}'),
      ),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      catalogRepositoryProvider.overrideWithValue(catalog),
      brandsProvider.overrideWith((ref) async => kSampleBrands),
      hubAppOverride(hubApp),
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
  if (tapped) {
    await tester.tap(find.text('TAP'));
  } else {
    router.go(link);
  }
  await tester.pumpAndSettle();
  return (router: router, catalog: catalog);
}

const _build2 = HubAppState.available(kSampleHmAppConfig);
const _build1 = HubAppState.unavailable();

void main() {
  group('sellerCodeOf', () {
    test('reads the seller code after the store view', () {
      expect(sellerCodeOf(_seller), 'loly');
      expect(
        sellerCodeOf('https://hub-market.magento2.click/en/shop/mia-co'),
        'mia-co',
      );
      expect(
        sellerCodeOf('https://hub-market.magento2.click/shop/loly'),
        'loly',
      );
    });

    test('a deeper page belongs to the seller too', () {
      expect(
        sellerCodeOf('https://hub-market.magento2.click/ar/shop/loly/items/'),
        'loly',
      );
    });

    test('store-relative paths, as promos carry them', () {
      expect(sellerCodeOf('shop/loly'), 'loly');
      expect(sellerCodeOf('/shop/loly/'), 'loly');
    });

    test('the sellers index is empty', () {
      expect(sellerCodeOf('https://hub-market.magento2.click/en/shop/'), '');
      expect(
        sellerCodeOf('https://hub-market.magento2.click/en/sellerlist'),
        '',
      );
    });

    test('anything else is no seller', () {
      for (final url in [
        'https://hub-market.magento2.click/en/shopbrand/Mancera.html',
        'https://hub-market.magento2.click/en/furniture.html',
        'https://hub-market.magento2.click/en/shop-by-brand/x',
        'https://hub-market.magento2.click/en/',
        '',
      ]) {
        expect(sellerCodeOf(url), isNull, reason: url);
      }
    });
  });

  group('openStorefrontUrl', () {
    testWidgets('with the seller API a seller link opens its store page', (
      tester,
    ) async {
      final opened = await _open(tester, link: _seller, hubApp: _build2);

      expect(find.text('STORE loly'), findsOneWidget);
      // No urlResolver round trip.
      expect(opened.catalog.resolvedUrl, isNull);
    });

    testWidgets('the sellers index opens the stores list', (tester) async {
      await _open(
        tester,
        link: 'https://hub-market.magento2.click/uae-en/shop/',
        hubApp: _build2,
      );

      expect(find.text('STORES'), findsOneWidget);
    });

    testWidgets('Build 1 keeps the website', (tester) async {
      await _open(tester, link: _seller, hubApp: _build1);

      expect(find.text('WEB $_seller'), findsOneWidget);
      expect(find.textContaining('STORE'), findsNothing);
    });

    testWidgets('a probe that could not tell keeps the website', (
      tester,
    ) async {
      await _open(tester, link: _seller, hubApp: const HubAppState.unknown());

      expect(find.text('WEB $_seller'), findsOneWidget);
    });
  });

  group('App Links', () {
    testWidgets('a seller link opens the store page over Home', (tester) async {
      final opened = await _open(
        tester,
        link: _seller,
        hubApp: _build2,
        tapped: false,
      );

      expect(find.text('STORE loly'), findsOneWidget);
      expect(opened.catalog.resolvedUrl, isNull);
      opened.router.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('Build 1 keeps the website', (tester) async {
      await _open(tester, link: _seller, hubApp: _build1, tapped: false);

      // go_router drops the trailing slash from the location.
      expect(
        find.text('WEB https://hub-market.magento2.click/uae-en/shop/loly'),
        findsOneWidget,
      );
    });
  });
}
