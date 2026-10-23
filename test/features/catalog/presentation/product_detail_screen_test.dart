import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/util/launch.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/brands_provider.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/brand.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/search_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/pdp_buy_bar.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/features/cms/presentation/widgets/cms_html_view.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/personalization/data/insights_tracker.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/insights_fakes.dart';
import '../../../support/pdp_fixtures.dart';
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

  // QA TC107: the cart screen read a 503 from the edge as "the store is
  // temporarily unavailable" while Add to Cart said "Something went wrong"
  // for the same outage. The sticky bar reports what actually failed.
  group('a refused Add to Cart says what failed', () {
    final lamp = ProductDetail(
      sku: 'HM-SIMPLE-1',
      name: 'Desk Lamp',
      urlKey: 'desk-lamp',
      typeId: 'simple',
      regularPrice: const Money(amount: 100, currency: 'AED'),
      finalPrice: const Money(amount: 100, currency: 'AED'),
    );

    Future<void> tapAdd(WidgetTester tester, Failure failure) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cart = FakeCartRepository()..addProductsFailure = failure;
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(lamp),
          initialLocation: '/product/desk-lamp',
          overrides: [cartRepositoryProvider.overrideWithValue(cart)],
        ),
      );
      await tester.pumpAndSettle();

      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.byWidget(_addToCart(tester, l10n)));
      await tester.pumpAndSettle();
    }

    testWidgets('the edge is down: the store-unavailable line', (tester) async {
      await tapAdd(tester, const Failure(FailureKind.service));

      expect(
        find.text(
          'The store is temporarily unavailable. Please try again shortly.',
        ),
        findsOneWidget,
      );
      expect(find.text('Something went wrong. Please try again.'), findsNothing);
    });

    testWidgets("the store's own refusal reaches the shopper", (tester) async {
      await tapAdd(
        tester,
        const Failure(
          FailureKind.server,
          detail: 'The requested qty is not available',
        ),
      );

      expect(find.text('The requested qty is not available'), findsOneWidget);
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

  // QA TC102: "added media (an image or a video, in the short or the long
  // description) does not show on the app".
  group('the description shows what the seller put in it', () {
    quietNetworkImages();

    const picture =
        '<figure data-content-type="image"><img '
        'class="pagebuilder-mobile-hidden" '
        'src="https://hub-market.magento2.click/media/wysiwyg/a.jpg">'
        '<img class="pagebuilder-mobile-only" '
        'src="https://hub-market.magento2.click/media/wysiwyg/a.jpg"></figure>';
    const video =
        '<div data-content-type="video"><iframe '
        'src="https://www.youtube.com/embed/Rl6EvEeN348?autoplay=1&amp;mute=1">'
        '</iframe></div>';

    ProductDetail rich({
      String? description,
      String? html,
      String? short,
      String? shortHtml,
    }) => ProductDetail(
      sku: kSampleDetail.sku,
      name: kSampleDetail.name,
      urlKey: kSampleDetail.urlKey,
      regularPrice: kSampleDetail.regularPrice,
      finalPrice: kSampleDetail.finalPrice,
      description: description,
      descriptionBlocks: html == null
          ? const []
          : CmsDocument.parse(html, embeds: true),
      shortDescription: short,
      shortDescriptionBlocks: shortHtml == null
          ? const []
          : CmsDocument.parse(shortHtml, embeds: true),
    );

    Future<void> tall(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 4200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    Future<void> open(WidgetTester tester, AppLocalizations l10n) async {
      await tester.tap(find.text(l10n.pdpDescriptionMaterial));
      await tester.pumpAndSettle();
    }

    testWidgets('a picture and a video, in the description and the short one', (
      tester,
    ) async {
      await tall(tester);
      final launched = <Uri>[];
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(
            rich(
              description: 'Great sound',
              html: '<p>Great sound</p>$picture$video',
              short: 'Two lines',
              shortHtml:
                  '<p>Two lines</p>'
                  '<img src="https://hub-market.magento2.click/media/b.png">',
            ),
          ),
          launched: launched,
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await open(tester, l10n);

      expect(find.text('Great sound'), findsOneWidget);
      expect(find.text(l10n.tabKeyFeatures), findsOneWidget);
      expect(find.text('Two lines'), findsOneWidget);
      // One picture in the description (its desktop and mobile copies drawn
      // once) and one in the short description.
      expect(
        find.descendant(
          of: find.byType(CmsHtmlView),
          matching: find.byType(HubImage),
        ),
        findsNWidgets(2),
      );
      expect(find.text(l10n.cmsWatchVideo), findsOneWidget);

      // A tap on the video hands the player's own page to the platform.
      await tester.tap(find.text(l10n.cmsWatchVideo));
      expect(launched, [Uri.parse('https://www.youtube.com/watch?v=Rl6EvEeN348')]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a description that is a picture alone still has its accordion', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(rich(html: picture)),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));

      expect(find.text(l10n.pdpDescriptionMaterial), findsOneWidget);
      await open(tester, l10n);
      expect(
        find.descendant(
          of: find.byType(CmsHtmlView),
          matching: find.byType(HubImage),
        ),
        findsOneWidget,
      );
      // No words, so no "Key features" heading above anything.
      expect(find.text(l10n.tabKeyFeatures), findsNothing);
    });

    testWidgets('a short description with a picture alone is under its heading', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(
            rich(
              description: 'Sturdy and light',
              html: '<p>Sturdy and light</p>',
              shortHtml: '<img src="https://hub-market.magento2.click/m/c.png">',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await open(tester, l10n);

      expect(find.text(l10n.tabKeyFeatures), findsOneWidget);
      expect(find.byType(HubImage), findsWidgets);
    });

    testWidgets('a page built from plain text alone shows that text, as before', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(
        _harness(
          'en',
          repository: _DetailRepository(rich(description: 'Just words')),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('en'));
      await open(tester, l10n);

      expect(find.text('Just words'), findsOneWidget);
      expect(find.byType(CmsHtmlView), findsNothing);
    });

    testWidgets('Arabic: the same, right to left, without an overflow', (
      tester,
    ) async {
      await tall(tester);
      await tester.pumpWidget(
        _harness(
          'ar',
          repository: _DetailRepository(
            rich(
              description: 'صوت رائع',
              html: '<p>صوت رائع</p>$picture$video'
                  '<ul><li>ضمان سنتين</li></ul>',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('ar'));
      await open(tester, l10n);

      expect(find.text('صوت رائع'), findsOneWidget);
      expect(find.text('ضمان سنتين'), findsOneWidget);
      expect(find.text('شاهد الفيديو'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
