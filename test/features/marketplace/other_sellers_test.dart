import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_route_query.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/pdp_buy_bar.dart';
import 'package:hubmarket_app/features/marketplace/presentation/other_sellers.dart';
import 'package:hubmarket_app/features/marketplace/presentation/seller_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';
import 'marketplace_harness.dart' show aed, phoneView;
import 'product_offers_test.dart' show offerJson;
import 'package:hubmarket_app/app/theme/hub_icons.dart';

/// The Joust Duffle Bag family of 30 Sep 2026: the main product sold by
/// test_1 (AED 28.90 after a special price), and two other sellers.
ProductDetail _duffle({String sku = '24-MB01', String urlKey = 'joust-duffle-bag'}) =>
    ProductDetail(
      sku: sku,
      name: 'Joust Duffle Bag',
      urlKey: urlKey,
      typeId: 'simple',
      regularPrice: aed(34),
      finalPrice: aed(28.9),
      description: 'Big enough to haul a basketball and some sneakers.',
    );

Map<String, dynamic> _mainItem({List<Map<String, dynamic>>? offers}) {
  final list =
      offers ??
      [
        offerJson(
          2287,
          'ENARA',
          'ENARA',
          price: 34,
          rating: 4.4,
          dispatch: {'code': 'days_2_3', 'label': '2-3 days', 'source': 'DECLARED'},
        ),
        offerJson(
          2150,
          'hassan1',
          'Hassan Store',
          price: 40,
          regular: 45,
          dispatch: {'code': 'next_day', 'label': 'Next business day', 'source': 'DECLARED'},
        ),
      ];
  return {
    '__typename': 'SimpleProduct',
    'sku': '24-MB01',
    'hm_seller': sellerJson('test_1', 'Test 1', rating: 4.7),
    'hm_offer_count': list.length,
    'hm_other_offers': list,
  };
}

/// Hassan Store's offer page, read by its URL: its other sellers are the main
/// product and ENARA.
Map<String, dynamic> _offerPage() => {
  '__typename': 'SimpleProduct',
  'sku': 'SKU-2150',
  'hm_seller': sellerJson('hassan1', 'Hassan Store'),
  'hm_offer_count': 2,
  'hm_other_offers': [
    offerJson(1, 'test_1', 'Test 1', price: 28.9, regular: 34),
    offerJson(2287, 'ENARA', 'ENARA', price: 34),
  ],
};

/// The public client: the main product by url_key; an offer, which product
/// search leaves out, only by its URL.
RecordingGraphQLClient _public({List<Map<String, dynamic>>? offers}) =>
    RecordingGraphQLClient((request, document) {
      final key = request.variables['urlKey'];
      if (key != null) {
        return {
          'products': {
            'items': [if (key == 'joust-duffle-bag') _mainItem(offers: offers)],
          },
        };
      }
      return {'route': request.variables['url'] == 'offer-2150.html' ? _offerPage() : null};
    });

/// The catalogue: only the main product is found by url_key.
class _Catalog extends FakeCatalogRepository {
  @override
  Future<ProductDetail?> fetchProductDetail(String urlKey) async =>
      urlKey == 'joust-duffle-bag' ? _duffle() : null;
}

/// Offer pages by URL.
class _Routes extends ProductRouteRepository {
  _Routes() : super(fakeGraphQLClient());

  @override
  Future<ProductDetail?> fetchDetail(String url) async =>
      url == 'offer-2150.html' ? _duffle(sku: 'SKU-2150', urlKey: 'offer-2150') : null;
}

/// Records what went into the cart.
class _Cart extends FakeCartRepository {
  final List<Map<String, dynamic>> added = [];

  @override
  Future<Cart> addProducts(
    String cartId,
    List<Map<String, dynamic>> items, {
    bool throwOnUserError = true,
  }) {
    added.addAll(items);
    return super.addProducts(cartId, items, throwOnUserError: throwOnUserError);
  }
}

Widget _app({
  required String locale,
  required RecordingGraphQLClient public,
  required _Cart cart,
  HubAppState hubApp = const HubAppState.available(kSampleHmAppConfig),
  GlobalKey? boundary,
}) {
  final router = GoRouter(
    initialLocation: AppRoutes.product('joust-duffle-bag'),
    routes: [
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) =>
            ProductDetailScreen(urlKey: state.pathParameters['urlKey']!),
      ),
      GoRoute(
        path: '/store/:code',
        builder: (_, state) =>
            Scaffold(body: Text('store page ${state.pathParameters['code']}')),
      ),
      for (final path in [
        AppRoutes.home,
        AppRoutes.cart,
        AppRoutes.categories,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.checkout,
        AppRoutes.search,
      ])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(path))),
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
      localCacheProvider.overrideWithValue(
        FakeLocalCache()..writeString('guest_cart_id', 'guest-1'),
      ),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      hubAppOverride(hubApp),
      publicGraphqlClientProvider.overrideWithValue(public.client),
      cartRepositoryProvider.overrideWithValue(cart),
      catalogRepositoryProvider.overrideWithValue(_Catalog()),
      productRouteRepositoryProvider.overrideWithValue(_Routes()),
      freeShippingThresholdProvider.overrideWith((ref) async => null),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Riyadh'),
      storeFeaturesProvider.overrideWith((ref) async => StoreFeatures.none),
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
    ],
    child: boundary == null ? app : RepaintBoundary(key: boundary, child: app),
  );
}

/// The operation names the public client was asked, in order.
List<String?> _operations(RecordingGraphQLClient client) => [
  for (final request in client.requests) operationNameOf(request),
];

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('Figma 14: the "Sold by N other sellers" card lists the offers '
        '($locale)', (tester) async {
      phoneView(tester, height: 1000);
      final key = GlobalKey();
      final public = _public();
      await tester.pumpWidget(
        _app(locale: locale, public: public, cart: _Cart(), boundary: key),
      );
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'pdp_other_sellers_$locale');

      final card = find.byType(OtherSellersCard);
      expect(card, findsOneWidget);
      expect(find.text(l10n.pdpOtherSellers(2)), findsOneWidget);
      expect(find.text(l10n.pdpOtherSellersCompare), findsOneWidget);
      // After the seller and the title, as the frame orders them.
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester.getTopLeft(find.byType(SoldByRow)).dy),
      );
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester.getTopLeft(find.text('Joust Duffle Bag').first).dy),
      );
      // The cheapest offers are on the card itself, each with its "+".
      expect(
        find.descendant(of: card, matching: find.byType(OfferTile)),
        findsNWidgets(2),
      );
      expect(find.descendant(of: card, matching: find.text('ENARA')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('AED 34')), findsOneWidget);
      expect(find.byTooltip(l10n.offerAddToCart('ENARA')), findsOneWidget);
      // One public read, with the offers.
      expect(_operations(public), ['HmProductMarketplace']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Compare" opens the sheet, which lists the offers cheapest '
        'first ($locale)', (tester) async {
      phoneView(tester);
      final key = GlobalKey();
      await tester.pumpWidget(
        _app(locale: locale, public: _public(), cart: _Cart(), boundary: key),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.pdpOtherSellersCompare));
      await tester.pumpAndSettle();
      await captureScreen(tester, key, 'pdp_other_sellers_sheet_$locale');

      final sheet = find.byType(OtherSellersSheet);
      expect(sheet, findsOneWidget);
      // The card on the page lists the same two; the sheet its own.
      expect(
        find.descendant(of: sheet, matching: find.byType(OfferTile)),
        findsNWidgets(2),
      );
      Finder inSheet(String text) =>
          find.descendant(of: sheet, matching: find.text(text));
      expect(inSheet(l10n.pdpOtherSellers(2)), findsOneWidget);
      expect(inSheet('ENARA'), findsOneWidget);
      expect(inSheet('Hassan Store'), findsOneWidget);
      expect(inSheet('AED 34'), findsOneWidget);
      expect(inSheet('AED 40'), findsOneWidget);
      expect(inSheet('AED 45'), findsOneWidget, reason: 'struck through');
      expect(inSheet('2-3 days'), findsOneWidget);
      expect(inSheet('Next business day'), findsOneWidget);
      expect(inSheet('4.4'), findsOneWidget);
      expect(
        tester.getTopLeft(inSheet('ENARA')).dy,
        lessThan(tester.getTopLeft(inSheet('Hassan Store')).dy),
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.byTooltip(l10n.offerAddToCart('ENARA')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('"+" adds the offer the way the page adds: its SKU, the page\'s '
      'quantity, then "Added to cart"', (tester) async {
    phoneView(tester, height: 1000);
    final cart = _Cart();
    await tester.pumpWidget(_app(locale: 'en', public: _public(), cart: cart));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    // Quantity 2 on the page.
    await tester.tap(
      find.descendant(
        of: find.byType(QuantityPill),
        matching: find.byIcon(HubIcons.plus),
      ),
    );
    await tester.pumpAndSettle();
    // The "+" on ENARA's row of the card.
    await tester.tap(find.byTooltip(l10n.offerAddToCart('ENARA')));
    await tester.pumpAndSettle();

    expect(cart.added, [
      {'sku': 'SKU-2287', 'quantity': 2},
    ]);
    expect(find.byType(OtherSellersSheet), findsNothing);
    expect(find.text(l10n.cartAdded), findsOneWidget);
  });

  testWidgets('"+" in the Compare sheet adds the offer the same way', (
    tester,
  ) async {
    phoneView(tester, height: 1000);
    final cart = _Cart();
    await tester.pumpWidget(_app(locale: 'en', public: _public(), cart: cart));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    await tester.tap(find.text(l10n.pdpOtherSellersCompare));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(OtherSellersSheet),
        matching: find.byTooltip(l10n.offerAddToCart('ENARA')),
      ),
    );
    await tester.pumpAndSettle();

    expect(cart.added, [
      {'sku': 'SKU-2287', 'quantity': 1},
    ]);
    expect(find.byType(OtherSellersSheet), findsNothing);
    expect(find.text(l10n.cartAdded), findsOneWidget);
  });

  testWidgets('an offer opens its own page, read by its URL, with its seller '
      'and the other sellers', (tester) async {
    phoneView(tester, height: 1000);
    final public = _public();
    await tester.pumpWidget(_app(locale: 'en', public: public, cart: _Cart()));
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));

    // Its row on the card.
    await tester.tap(find.text('Hassan Store'));
    await tester.pumpAndSettle();

    expect(find.byType(OtherSellersSheet), findsNothing);
    expect(
      find.descendant(of: find.byType(SoldByRow), matching: find.text('Hassan Store')),
      findsOneWidget,
    );
    expect(find.text(l10n.pdpOtherSellers(2)), findsOneWidget);
    expect(_operations(public), [
      'HmProductMarketplace',
      'HmProductMarketplace',
      'HmProductMarketplaceByRoute',
    ]);
    expect(public.requests.last.variables, {'url': 'offer-2150.html'});
  });

  testWidgets('an offer bought with options is chosen on its own page', (
    tester,
  ) async {
    phoneView(tester);
    final cart = _Cart();
    await tester.pumpWidget(
      _app(
        locale: 'en',
        cart: cart,
        public: _public(
          offers: [
            {
              ...offerJson(2150, 'hassan1', 'Hassan Store', price: 40),
              'type_id': 'configurable',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.pdpOtherSellers(1)), findsOneWidget);

    expect(find.byTooltip(l10n.offerAddToCart('Hassan Store')), findsNothing);
    await tester.tap(
      find.byTooltip(l10n.offerChooseOptions('Hassan Store')),
    );
    await tester.pumpAndSettle();

    expect(cart.added, isEmpty);
    expect(
      find.descendant(of: find.byType(SoldByRow), matching: find.text('Hassan Store')),
      findsOneWidget,
    );
  });

  testWidgets('no other seller, no row', (tester) async {
    phoneView(tester);
    await tester.pumpWidget(
      _app(locale: 'en', public: _public(offers: const []), cart: _Cart()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SoldByRow), findsOneWidget);
    expect(find.byType(OtherSellersCard), findsNothing);
  });

  testWidgets('Build 1: no row and no second request', (tester) async {
    phoneView(tester);
    final public = _public();
    await tester.pumpWidget(
      _app(
        locale: 'en',
        public: public,
        cart: _Cart(),
        hubApp: const HubAppState.unavailable(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(OtherSellersCard), findsNothing);
    expect(public.requests, isEmpty);
  });
}
