import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/bundle_product_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/bundle_fixtures.dart';
import '../../../support/fonts.dart';
import '../../../support/hubapp_fakes.dart';
import '../../../support/marketplace_fakes.dart';
import '../../../support/pdp_fixtures.dart';
import '../../marketplace/marketplace_harness.dart';

// Opening the Bose headphones from a search showed the "Gaming Set" bundle. The
// store answers the headphones' url_key with the bundle that offers them, and
// the bundle came first; the page read the first item, twice (the product and
// HubApp's extras), so the bundle's page was built for the headphones' link.
// Here the page runs on the real repositories, fed the store's answer.

const _boseName = 'Bose 700 Noise Cancelling Headphones, Bluetooth, Wireless, Mic';

Map<String, dynamic> _money(double value) => {'value': value, 'currency': 'AED'};

/// `products.items` for ProductDetail, bundle first as the store sends it.
Map<String, dynamic> _detailAnswer() => {
  'products': {
    'items': [
      {
        '__typename': 'BundleProduct',
        'sku': 'Gaming Set',
        'name': 'Gaming Set',
        'url_key': 'gaming-set',
        'stock_status': 'IN_STOCK',
      },
      {
        '__typename': 'SimpleProduct',
        'sku': '794297-0100',
        'name': _boseName,
        'url_key': 'bose-700',
        'stock_status': 'IN_STOCK',
        'price_range': {
          'minimum_price': {
            'regular_price': _money(1666),
            'final_price': _money(1666),
          },
        },
      },
    ],
  },
};

/// HubApp's extras for the same two products, bundle first.
Map<String, dynamic> _extrasAnswer() => {
  'products': {
    'items': [
      {...fitnessPackJson(), 'url_key': 'gaming-set'},
      {
        '__typename': 'SimpleProduct',
        'sku': '794297-0100',
        'url_key': 'bose-700',
        'hm_seller': sellerJson('hassan1', 'Hassan1'),
      },
    ],
  },
};

Widget _page(String urlKey) => marketplaceHarness(
  locale: 'en',
  location: AppRoutes.product(urlKey),
  catalogRepository: CatalogRepository(
    fakeHubAppClient({'ProductDetail': _detailAnswer()}),
  ),
  publicAnswers: {'HmProductMarketplace': _extrasAnswer()},
  cmsBlocks: {'hm_home_trust': kTrustBlockEn},
);

void main() {
  setUpAll(loadAppFonts);
  quietNetworkImages();

  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('a product inside a bundle opens its own page, not the bundle\'s', (
    tester,
  ) async {
    phoneView(tester, height: 2400);
    await tester.pumpWidget(_page('bose-700'));
    await tester.pumpAndSettle();

    expect(find.byType(BundleProductScreen), findsNothing);
    expect(find.text('Items in this package'), findsNothing);
    expect(find.text(l10n.bundleAddToCart), findsNothing);
    expect(find.text(_boseName), findsWidgets);
    // Its own seller, from the product's extras and not the bundle's.
    expect(find.text('Hassan1'), findsWidgets);
    expect(find.text('Test 1'), findsNothing);
    // And an ordinary buy bar: Add to cart with its own price.
    expect(find.textContaining(l10n.pdpAddToCart), findsWidgets);
    expect(find.textContaining('1,666'), findsWidgets);
  });

  testWidgets('the bundle still opens its page by its own link', (tester) async {
    phoneView(tester, height: 2400);
    await tester.pumpWidget(_page('gaming-set'));
    await tester.pumpAndSettle();

    expect(find.byType(BundleProductScreen), findsOneWidget);
    expect(find.text('Items in this package'), findsOneWidget);
    expect(find.text(_boseName), findsNothing);
  });
}
