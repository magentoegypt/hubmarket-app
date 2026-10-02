import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/util/launch.dart';
import 'package:hubmarket_app/features/catalog/data/brands_provider.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/pdp_buy_bar.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/personalization/data/insights_tracker.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/insights_fakes.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

/// Serves one canned [ProductDetail] instead of the shared sample.
class _DetailRepository extends FakeCatalogRepository {
  _DetailRepository(this.detail);
  final ProductDetail detail;

  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async => detail;
}

Widget _harness(
  String locale, {
  CatalogRepository? repository,
  HubAppState hubApp = const HubAppState.unavailable(),
  Map<String, String>? cmsBlocks,
  List<Brand>? brands,
  List<Uri>? launched,
  GlobalKey? boundary,
  String initialLocation = '/product/coco-mademoiselle',
  List<Override> overrides = const [],
}) {
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) =>
            ProductDetailScreen(urlKey: state.pathParameters['urlKey']!),
      ),
      GoRoute(
        path: '/brand/:urlKey',
        builder: (_, state) => Scaffold(
          body: Text('brand page ${state.pathParameters['urlKey']}'),
        ),
      ),
      for (final p in [
        '/home',
        '/categories',
        '/cart',
        '/wishlist',
        '/account',
        '/search',
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  final app = MaterialApp.router(
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
  );
  return ProviderScope(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      catalogRepositoryProvider.overrideWithValue(
        repository ?? FakeCatalogRepository(),
      ),
      // Keep the PDP test network-free.
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      publicGraphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      // The product page asks HubApp for its seller; Build 1 by default.
      hubAppOverride(hubApp),
      if (cmsBlocks != null)
        homeCmsBlocksProvider.overrideWith((ref) async => cmsBlocks),
      if (brands != null) brandsProvider.overrideWith((ref) async => brands),
      externalUriLauncherProvider.overrideWithValue((uri) async {
        launched?.add(uri);
        return true;
      }),
      ...overrides,
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// The live `hm_home_trust` block (Content › Blocks), EN and AR.
const String _trustEn =
    '<div class="hm-trust">'
    '<div class="hm-trust__item"><span class="hm-trust__title">Trusted Sellers'
    '</span><span class="hm-trust__text">Verified &amp; approved</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">Secure Payments'
    '</span><span class="hm-trust__text">Cash on delivery, Visa, Mastercard'
    '</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">Fast Delivery'
    '</span><span class="hm-trust__text">Nationwide</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">Easy Returns'
    '</span><span class="hm-trust__text">14-day return policy</span></div>'
    '</div>';
const String _trustAr =
    '<div class="hm-trust">'
    '<div class="hm-trust__item"><span class="hm-trust__title">بائعون موثوقون'
    '</span><span class="hm-trust__text">تمت المراجعة والاعتماد</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">مدفوعات آمنة'
    '</span><span class="hm-trust__text">الدفع عند الاستلام وفيزا وماستركارد'
    '</span></div>'
    '<div class="hm-trust__item"><span class="hm-trust__title">توصيل سريع'
    '</span><span class="hm-trust__text">لجميع المناطق</span></div>'
    '</div>';

/// A core bundle, as the plain page shows it without the Hub Market App.
ProductDetail _bundle({bool inStock = true}) => ProductDetail(
  sku: 'HM-DEMO-BUNDLE-FITNESS',
  name: 'Home Fitness Starter Pack',
  urlKey: 'home-fitness-starter-pack',
  typeId: 'bundle',
  inStock: inStock,
  regularPrice: const Money(amount: 72, currency: 'AED'),
  finalPrice: const Money(amount: 60.56, currency: 'AED'),
);

/// The sticky bar's Add to cart button (a `FilledButton.icon`, a subclass:
/// `find.byType` is an exact-type match, so it looks for the subtype by test).
FilledButton _addToCart(WidgetTester tester, AppLocalizations l10n) =>
    tester.widget<FilledButton>(
      find.ancestor(
        of: find.textContaining(l10n.pdpAddToCart),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('opening the page tells Algolia Personalization the product was '
      'viewed, once', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final insights = RecordingInsightsTracker();
    await tester.pumpWidget(
      _harness(
        'en',
        overrides: [insightsTrackerProvider.overrideWithValue(insights)],
      ),
    );
    await tester.pumpAndSettle();

    expect(insights.calls, ['view:CHANEL-COCO']);

    // Choosing a variant rebuilds the page: still one view.
    await tester.tap(find.text('100ml'));
    await tester.pumpAndSettle();
    expect(insights.calls, ['view:CHANEL-COCO']);
  });

  testWidgets('renders product detail and updates price on variant select', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    expect(find.text('Coco Mademoiselle EDP'), findsWidgets);
    expect(find.text('AED 199'), findsWidgets);

    await tester.tap(find.text('100ml'));
    await tester.pumpAndSettle();

    expect(find.text('AED 299'), findsWidgets);
  });

  testWidgets('"Ratings & reviews" shows the empty state (store has zero '
      'reviews) and still invites the first one', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    expect(find.text('Ratings & reviews'), findsOneWidget);
    expect(find.text('No reviews yet'), findsOneWidget);
    expect(find.text('Write a review'), findsOneWidget);
    // No stars, no bars and no "See all" for reviews nobody wrote.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('See all'), findsNothing);
  });

  testWidgets('"Ratings & reviews" draws the per-star bars from the loaded '
      'reviews', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    ProductReview review(int averageRating) => ProductReview(
      nickname: 'Hub Market Demo',
      summary: 'Good value',
      text: '',
      averageRating: averageRating,
      date: '2026-08-27 14:18:40',
    );
    await tester.pumpWidget(
      _harness(
        'en',
        repository: _DetailRepository(
          ProductDetail(
            sku: kSampleDetail.sku,
            name: kSampleDetail.name,
            urlKey: kSampleDetail.urlKey,
            ratingSummary: 93,
            reviewCount: 3,
            reviews: [review(100), review(100), review(80)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bars = tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .map((bar) => bar.value)
        .toList();
    // 5★ → 1★: two of three reviews are 5★, one is 4★.
    expect(bars, [0.67, 0.33, 0.0, 0.0, 0.0]);
    // The rating line under the title and the summary both say it.
    expect(find.text('3 reviews'), findsNWidgets(2));
    expect(find.text('See all 3'), findsOneWidget);
    // The newest review, in its own card.
    expect(find.text('Good value'), findsOneWidget);
  });

  testWidgets('"Looking similar" hides when the product links nothing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness('en'));
    await tester.pumpAndSettle();

    expect(find.text('Looking similar'), findsNothing);
  });

  testWidgets('"Looking similar" lists the linked products', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(
        'en',
        repository: _DetailRepository(
          ProductDetail(
            sku: kSampleDetail.sku,
            name: kSampleDetail.name,
            urlKey: kSampleDetail.urlKey,
            regularPrice: kSampleDetail.regularPrice,
            finalPrice: kSampleDetail.finalPrice,
            alsoLike: [kSampleProducts[1]],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Looking similar'), findsOneWidget);
    expect(find.text('Sauvage EDT'), findsOneWidget);
    // Without a category on the product there is nowhere for "See all" to go.
    expect(find.text('See all'), findsNothing);
  });

  group('a bundle on the plain page (no Hub Market App bundles)', () {
    setUpAll(loadAppFonts);

    for (final locale in ['en', 'ar']) {
      testWidgets('Add to Cart stays off; the note opens the website '
          '($locale)', (tester) async {
        await _phone(tester);
        final key = GlobalKey();
        final launched = <Uri>[];
        await tester.pumpWidget(
          _harness(
            locale,
            repository: _DetailRepository(_bundle()),
            initialLocation: '/product/home-fitness-starter-pack',
            launched: launched,
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'pdp_bundle_web_only_$locale');

        final l10n = lookupAppLocalizations(Locale(locale));
        // Magento refuses a bundle SKU without its options: never offered.
        expect(_addToCart(tester, l10n).onPressed, isNull);
        expect(find.text(l10n.pdpBundleOnWebsite), findsOneWidget);

        await tester.tap(find.text(l10n.pdpBundleOpenWebsite));
        await tester.pumpAndSettle();
        // The bundle's own storefront page, in the store view's language.
        expect(launched, [
          Uri.parse(
            'https://hub-market.magento2.click/uae-$locale/'
            'home-fitness-starter-pack.html',
          ),
        ]);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('out of stock: no website note either', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(_bundle(inStock: false)),
          initialLocation: '/product/home-fitness-starter-pack',
        ),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      // Under the rating, and on the bar's button.
      expect(find.text(l10n.productOutOfStock), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(PdpBuyBar),
          matching: find.text(l10n.productOutOfStock),
        ),
        findsOneWidget,
      );
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.descendant(
            of: find.byType(PdpBuyBar),
            matching: find.text(l10n.productOutOfStock),
          ),
          matching: find.byWidgetPredicate((widget) => widget is FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text(l10n.pdpBundleOnWebsite), findsNothing);
    });

    testWidgets('a configurable still waits for its options', (tester) async {
      // Tall enough that the sizes show without scrolling the bar away.
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_harness('en'));
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(_addToCart(tester, l10n).onPressed, isNull);
      expect(find.text(l10n.pdpBundleOnWebsite), findsNothing);

      await tester.tap(find.text('100ml'));
      await tester.pumpAndSettle();
      expect(_addToCart(tester, l10n).onPressed, isNotNull);
    });
  });

  group('delivery card from the hm_home_trust block', () {
    setUpAll(loadAppFonts);

    for (final locale in ['en', 'ar']) {
      testWidgets('shows the store\'s own items ($locale)', (tester) async {
        await _phone(tester);
        final key = GlobalKey();
        await tester.pumpWidget(
          _harness(
            locale,
            cmsBlocks: {'hm_home_trust': locale == 'ar' ? _trustAr : _trustEn},
            boundary: key,
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(PdpTrustRow));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'pdp_trust_row_$locale');

        // The card takes the block's delivery and returns items; the
        // trust and payment ones are the Home's.
        Finder icon(IconData data) => find.descendant(
          of: find.byType(PdpTrustRow),
          matching: find.byIcon(data),
        );
        if (locale == 'ar') {
          expect(find.text('توصيل سريع'), findsOneWidget);
          expect(find.text('لجميع المناطق'), findsOneWidget);
          expect(find.text('بائعون موثوقون'), findsNothing);
          expect(find.text('الدفع عند الاستلام وفيزا وماستركارد'), findsNothing);
          expect(find.text('شحن مجاني'), findsNothing);
          expect(icon(HubIcons.truck), findsOneWidget);
        } else {
          expect(find.text('Fast Delivery'), findsOneWidget);
          expect(find.text('Nationwide'), findsOneWidget);
          expect(find.text('Easy Returns'), findsOneWidget);
          expect(find.text('14-day return policy'), findsOneWidget);
          expect(find.text('Trusted Sellers'), findsNothing);
          expect(find.text('Secure Payments'), findsNothing);
          // The app's old claims are gone.
          expect(find.text('Free'), findsNothing);
          expect(find.text('easy returns'), findsNothing);
          // Glyphs follow each item's title first.
          expect(icon(HubIcons.truck), findsOneWidget);
          expect(icon(HubIcons.rotateCcw), findsOneWidget);
          expect(icon(HubIcons.shieldCheck), findsNothing);
          expect(icon(HubIcons.creditCard), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('no block, no card', (tester) async {
      await _phone(tester);
      // The CMS read fails in tests (offline client): nothing to show.
      await tester.pumpWidget(_harness('en'));
      await tester.pumpAndSettle();

      expect(find.byType(PdpTrustRow), findsNothing);
      expect(find.text('Trusted Sellers'), findsNothing);
      expect(find.text('Free'), findsNothing);
      expect(find.text('Verified'), findsNothing);
      expect(find.text('14-day'), findsNothing);
    });

    testWidgets('a block with neither delivery nor returns draws no card', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          cmsBlocks: {
            'hm_home_trust':
                '<div class="hm-trust"><div class="hm-trust__item">'
                '<span class="hm-trust__title">Trusted Sellers</span>'
                '<span class="hm-trust__text">Verified &amp; approved</span>'
                '</div></div>',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PdpTrustRow), findsNothing);
    });
  });

  group('the brand line opens the brand', () {
    ProductDetail branded() => ProductDetail(
      sku: kSampleDetail.sku,
      name: kSampleDetail.name,
      urlKey: kSampleDetail.urlKey,
      brand: 'Chanel',
      brandOptionId: 42,
      regularPrice: kSampleDetail.regularPrice,
      finalPrice: kSampleDetail.finalPrice,
    );

    Brand brand(String title, String urlKey, int optionId) => Brand(
      brandId: optionId,
      title: title,
      urlKey: urlKey,
      url: 'https://hub-market.magento2.click/uae-en/shopbrand/$urlKey.html',
      imageUrl: '',
      optionId: optionId,
      position: 0,
    );

    testWidgets('Build 2: its page (10e), matched by the mgs_brand option', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(branded()),
          hubApp: const HubAppState.available(kSampleHmAppConfig),
          brands: [
            brand('Chanel', 'chanel-old', 7),
            brand('Chanel Beauty', 'ChanelBeauty', 42),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chanel'));
      await tester.pumpAndSettle();
      expect(find.text('brand page ChanelBeauty'), findsOneWidget);
    });

    testWidgets('Build 1: the brand\'s products', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness('en', repository: _DetailRepository(branded())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chanel'));
      await tester.pumpAndSettle();
      final landing = tester.widget<SearchScreen>(find.byType(SearchScreen));
      expect(landing.brand?.title, 'Chanel');
      expect(landing.brand?.optionId, 42);
    });

    testWidgets('Build 2, brand not listed: the brand\'s products', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(branded()),
          hubApp: const HubAppState.available(kSampleHmAppConfig),
          brands: const [],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chanel'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);
    });
  });
}
