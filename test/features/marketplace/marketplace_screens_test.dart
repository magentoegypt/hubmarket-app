import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/cart/domain/bundle_cart_request.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/bundle_fixtures.dart';
import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/store_credit_fakes.dart';
import 'marketplace_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// The dress of Figma 14.
ProductDetail _dress() => ProductDetail(
  sku: 'LOLY-DR-0231',
  name: 'Floral Print Corset-Waist Tie Dress',
  urlKey: 'floral-dress',
  typeId: 'simple',
  regularPrice: aed(50),
  finalPrice: aed(50),
  description: 'Beautiful fabric.',
);

/// The fitness pack of Figma 14b.
ProductDetail _pack() => ProductDetail(
  sku: 'HM-DEMO-BUNDLE-FITNESS',
  name: 'Home Fitness Starter Pack',
  urlKey: 'home-fitness-starter-pack',
  typeId: 'bundle',
  shortDescription:
      'Everything you need to start training at home — four essentials '
      'from one seller, bundled at a saving over buying them one by one.',
  regularPrice: aed(72),
  finalPrice: aed(60.56),
);

Map<String, Object> _answer(Map<String, dynamic> item) => {
  'HmProductMarketplace': {
    'products': {
      'items': [item],
    },
  },
};

Map<String, dynamic> _dressItem({bool marketplace = false}) => {
  '__typename': 'SimpleProduct',
  'sku': 'LOLY-DR-0231',
  'hm_seller': marketplace
      ? sellerJson(null, 'Hub Market', marketplace: true)
      : sellerJson('loly', 'loly store', rating: 4.3),
};

void main() {
  // Real fonts: the test font's square glyphs would overflow rows that fit on
  // a device.
  setUpAll(loadAppFonts);

  group('Figma 14 — "Sold by" on the product page', () {
    testWidgets('names the seller and opens its store', (tester) async {
      phoneView(tester);
      final public = fakeHubAppClient(_answer(_dressItem()));
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('floral-dress'),
          catalogRepository: DetailRepository(_dress()),
          publicClient: public,
        ),
      );
      await tester.pumpAndSettle();

      // One public (GET) read, by url_key.
      expect(public.requests.map(operationNameOf), ['HmProductMarketplace']);
      expect(public.requests.single.variables, {'urlKey': 'floral-dress'});
      expect(find.text(_en.pdpSoldBy), findsOneWidget);
      expect(find.text('loly store'), findsOneWidget);
      // The frame's band carries no rating (the seller's 4.3 is not shown).
      expect(find.text('4.3'), findsNothing);

      await tester.tap(find.text(_en.pdpVisitStore));
      await tester.pumpAndSettle();
      expect(find.text('store page loly'), findsOneWidget);
    });

    testWidgets('without HubApp the page is as today and nothing is asked', (
      tester,
    ) async {
      phoneView(tester);
      final public = fakeHubAppClient(_answer(_dressItem()));
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('floral-dress'),
          hubApp: const HubAppState.unavailable(),
          catalogRepository: DetailRepository(_dress()),
          publicClient: public,
        ),
      );
      await tester.pumpAndSettle();

      expect(public.requests, isEmpty);
      expect(find.text(_en.pdpSoldBy), findsNothing);
      expect(find.text('Floral Print Corset-Waist Tie Dress'), findsOneWidget);
    });

    testWidgets("Hub Market's own products show no seller row", (tester) async {
      phoneView(tester);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('floral-dress'),
          catalogRepository: DetailRepository(_dress()),
          publicAnswers: _answer(_dressItem(marketplace: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.pdpSoldBy), findsNothing);
    });

    testWidgets('a build without the store page opens the website\'s', (
      tester,
    ) async {
      phoneView(tester);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('floral-dress'),
          catalogRepository: DetailRepository(_dress()),
          publicAnswers: _answer(_dressItem()),
          storeRoute: false,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.pdpVisitStore));
      await tester.pumpAndSettle();
      expect(
        find.text('web https://hub-market.magento2.click/en/shop/loly'),
        findsOneWidget,
      );
    });
  });

  group('Figma 14b — the bundle page', () {
    testWidgets('shows the package and adds it through hmAddBundleToCart', (
      tester,
    ) async {
      phoneView(tester, height: 1400);
      final cart = FakeCartRepository();
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('home-fitness-starter-pack'),
          catalogRepository: DetailRepository(_pack()),
          cartRepository: cart,
          publicAnswers: _answer(fitnessPackJson()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.bundleItemsTitle), findsOneWidget);
      expect(find.text(_en.bundleItemCount(4)), findsOneWidget);
      expect(find.text('Voyage Yoga Bag'), findsOneWidget);
      // Three rows, then "+1 more item".
      expect(find.text(_en.bundleMoreItems(1)), findsOneWidget);
      expect(find.text('Sprite Stasis Ball 55 cm'), findsNothing);
      await tester.tap(find.text(_en.bundleMoreItems(1)));
      await tester.pumpAndSettle();
      expect(find.text('Sprite Stasis Ball 55 cm'), findsOneWidget);

      expect(find.text('AED 60.56'), findsNWidgets(2)); // price + total
      expect(find.text(_en.bundleYouSave('AED 11.44')), findsOneWidget);
      expect(find.text(_en.bundleDiscountBadge(16)), findsOneWidget);

      await tester.tap(find.text(_en.bundleAddToCart));
      await tester.pumpAndSettle();

      expect(cart.bundleRequests.single.sku, 'HM-DEMO-BUNDLE-FITNESS');
      expect(cart.bundleRequests.single.selections.map((s) => s.selectionUid), [
        'YnVuZGxlLzIwLzYzLzE=',
        'YnVuZGxlLzIxLzY0LzE=',
        'YnVuZGxlLzIyLzY1LzE=',
        'YnVuZGxlLzIzLzY2LzE=',
      ]);
    });

    testWidgets('choices, a size and a quantity reach the mutation input', (
      tester,
    ) async {
      phoneView(tester, height: 1800);
      final cart = FakeCartRepository();
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('kit-builder'),
          catalogRepository: DetailRepository(
            ProductDetail(
              sku: 'KIT-BUILDER',
              name: 'Kit Builder',
              urlKey: 'kit-builder',
              typeId: 'bundle',
            ),
          ),
          cartRepository: cart,
          publicAnswers: _answer(kitBuilderJson()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.bundleMoreItems(1)));
      await tester.pumpAndSettle();

      // An incomplete package doesn't go: the first thing missing is said.
      await tester.tap(find.text(_en.bundleAddToCart));
      await tester.pumpAndSettle();
      expect(
        find.text(_en.bundleNeedsAttribute('Size', 'Training Top')),
        findsOneWidget,
      );
      expect(cart.bundleRequests, isEmpty);

      await tester.tap(find.text('M'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_en.bundleAddToCart));
      await tester.pumpAndSettle();
      expect(find.text(_en.bundleNeedsSelection('Mat')), findsOneWidget);
      expect(cart.bundleRequests, isEmpty);

      await tester.tap(find.text(_en.bundleChoose('Mat')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yoga Mat'));
      await tester.pumpAndSettle();

      // The bottle's own − 2 + stepper.
      final bottleRow = find
          .ancestor(of: find.text('Water Bottle'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: bottleRow, matching: find.byIcon(HubIcons.plus)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(_en.bundleAddToCart));
      await tester.pumpAndSettle();

      expect(cart.bundleRequests.single.selections, const [
        BundleSelectionInput(
          selectionUid: 'c2VsL3RvcA==',
          configurableOptionUids: ['Y29uZmlndXJhYmxlLzE0NC8xNjg='],
        ),
        BundleSelectionInput(selectionUid: 'c2VsL21hdA=='),
        BundleSelectionInput(selectionUid: 'c2VsL2JvdA==', quantity: 3),
      ]);
    });

    testWidgets('without HubApp a bundle opens the plain product page', (
      tester,
    ) async {
      phoneView(tester);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.product('home-fitness-starter-pack'),
          hubApp: const HubAppState.unavailable(),
          catalogRepository: DetailRepository(_pack()),
          publicAnswers: _answer(fitnessPackJson()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.bundleItemsTitle), findsNothing);
      expect(find.text(_en.bundleAddToCart), findsNothing);
      expect(find.text('Home Fitness Starter Pack'), findsOneWidget);
    });
  });

  group('Figma 16 — the cart by store', () {
    testWidgets('groups lines under their stores, one package each', (
      tester,
    ) async {
      phoneView(tester, height: 1400);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.cart,
          cartRepository: CannedCartRepository(twoStoreCart('guest-1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.cartSplitPackagesNote), findsOneWidget);
      expect(
        find.text('${_en.cartItemCount(4)} · ${_en.cartStoreCount(2)}'),
        findsOneWidget,
      );
      expect(find.text('MIA CO'), findsOneWidget);
      expect(find.text('loly store'), findsOneWidget);
      // The store's lines sit under its header.
      final mia = tester.getTopLeft(find.text('MIA CO')).dy;
      final loly = tester.getTopLeft(find.text('loly store')).dy;
      final sofa = tester.getTopLeft(find.text('Corner Sofa Bed')).dy;
      final dress = tester
          .getTopLeft(find.text('Floral Print Corset-Waist Tie Dress'))
          .dy;
      expect(mia < sofa && sofa < loly && loly < dress, isTrue);
    });

    testWidgets('without sellers the cart is one list, as today', (
      tester,
    ) async {
      phoneView(tester, height: 1400);
      final cart = twoStoreCart('guest-1');
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.cart,
          hubApp: const HubAppState.unavailable(),
          cartRepository: CannedCartRepository(
            Cart(
              id: cart.id,
              totalQuantity: cart.totalQuantity,
              totals: cart.totals,
              items: [
                for (final item in cart.items)
                  CartItem(
                    uid: item.uid,
                    sku: item.sku,
                    name: item.name,
                    quantity: item.quantity,
                    unitPrice: item.unitPrice,
                    rowTotal: item.rowTotal,
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.cartSplitPackagesNote), findsNothing);
      expect(find.text('MIA CO'), findsNothing);
      expect(find.text(_en.cartItemCount(4)), findsOneWidget);
      expect(find.text('Corner Sofa Bed'), findsOneWidget);
    });
  });

  group('the cart\'s store credit line', () {
    Future<void> pumpCart(
      WidgetTester tester, {
      required HubAppState hubApp,
      required FakeStoreCreditRepository credit,
      bool signedIn = true,
    }) async {
      phoneView(tester, height: 1500);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.cart,
          hubApp: hubApp,
          signedIn: signedIn,
          storeCredit: credit,
          cartRepository: CannedCartRepository(twoStoreCart('customer-1')),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('credit used at checkout shows under the delivery line', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository(
        cartCredit: sampleCartCredit(applied: 50),
      );
      await pumpCart(
        tester,
        hubApp: HubAppState.available(hubAppAccountConfig(storeCredit: true)),
        credit: credit,
      );

      expect(credit.calls, contains(startsWith('fetchCartCredit:')));
      expect(find.text(_en.checkoutStoreCredit), findsOneWidget);
      expect(find.text('−AED 50'), findsOneWidget);
    });

    testWidgets('no line while no credit is used', (tester) async {
      await pumpCart(
        tester,
        hubApp: HubAppState.available(hubAppAccountConfig(storeCredit: true)),
        credit: FakeStoreCreditRepository(cartCredit: sampleCartCredit()),
      );

      expect(find.text(_en.checkoutStoreCredit), findsNothing);
    });

    testWidgets('Build 1 and guests never ask', (tester) async {
      final build1 = FakeStoreCreditRepository(
        cartCredit: sampleCartCredit(applied: 50),
      );
      await pumpCart(
        tester,
        hubApp: const HubAppState.unavailable(),
        credit: build1,
      );
      expect(find.text(_en.checkoutStoreCredit), findsNothing);
      expect(build1.calls, isEmpty);

      final guest = FakeStoreCreditRepository(
        cartCredit: sampleCartCredit(applied: 50),
      );
      await pumpCart(
        tester,
        hubApp: HubAppState.available(hubAppAccountConfig(storeCredit: true)),
        credit: guest,
        signedIn: false,
      );
      expect(find.text(_en.checkoutStoreCredit), findsNothing);
      expect(guest.calls, isEmpty);
    });
  });

  group('Figma 22 — the order by store', () {
    testWidgets('one package per store', (tester) async {
      phoneView(tester, height: 1600);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.orderDetail,
          order: twoStoreOrder(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_en.orderPackageTitle(1, 'loly store')), findsOneWidget);
      expect(find.text(_en.orderPackageTitle(2, 'MIA CO')), findsOneWidget);
    });

    testWidgets('without sellers the items are one list, as today', (
      tester,
    ) async {
      phoneView(tester, height: 1600);
      await tester.pumpWidget(
        marketplaceHarness(
          locale: 'en',
          location: AppRoutes.orderDetail,
          order: twoStoreOrder(withSellers: false),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Package'), findsNothing);
      expect(find.text('Corner Sofa Bed'), findsOneWidget);
    });
  });
}
