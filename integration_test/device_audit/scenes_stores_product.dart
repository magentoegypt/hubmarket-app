import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/core/config/free_shipping.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/widgets/added_to_cart_sheet.dart';
import 'package:hubmarket_app/features/catalog/data/catalog_repository.dart';
import 'package:hubmarket_app/features/catalog/data/product_route_query.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_detail_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_reviews_screen.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/write_review_screen.dart';
import 'package:hubmarket_app/features/home/presentation/home_providers.dart';
import 'package:hubmarket_app/features/stores/presentation/screens/store_screen.dart';
import 'package:hubmarket_app/features/stores/presentation/screens/stores_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../test/support/bundle_fixtures.dart';
import '../../test/support/fakes.dart';
import '../../test/support/hubapp_fakes.dart';
import '../../test/support/pdp_fixtures.dart';
import 'audit_scene.dart';
import 'harness.dart';
import 'stores_product_fixtures.dart';

/// A server that lists the `vendors` capability: the store pages' extras (the
/// Reviews tab, Contact vendor, Sales and Call, the chips' counts).
const HubAppState _vendors = HubAppState.available(kVendorsHmAppConfig);

AppLocalizations _l10n(String locale) => lookupAppLocalizations(Locale(locale));

/// The stores screens' fakes: a server that lists the `vendors` capability and
/// answers [storesAnswers] on the public client, and the category tree.
AuditSetup _storesSetup(String locale) => AuditSetup(
  hubApp: _vendors,
  overrides: [storesPublicClient(locale), storesCatalog(locale)],
);

/// Opens the store page's tab called [label] (the front page's header turns
/// into the inside pages' app bar, Figma 13b).
Future<void> _openStoreTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await pumpFor(tester, 500);
}

/// Scrolls the screen's longest vertical scrollable back to its top (what
/// `ensureVisible` leaves behind when a tap had to scroll to its target).
void _toTop(WidgetTester tester) {
  ScrollPosition? best;
  for (final element in find.byType(Scrollable).evaluate()) {
    if (element is! StatefulElement) continue;
    final state = element.state;
    if (state is! ScrollableState) continue;
    final axis = state.axisDirection;
    if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
    final position = state.position;
    if (!position.hasContentDimensions) continue;
    if (best == null || position.maxScrollExtent > best.maxScrollExtent) {
      best = position;
    }
  }
  best?.jumpTo(best.minScrollExtent);
}

/// Taps [finder], scrolling the page to it first: on the phone the buy bar
/// and the fold hide what the test's tall surface showed.
Future<void> _tapScrolled(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await pumpFor(tester, 200);
  await tester.tap(finder);
  await pumpFor(tester, 300);
}

// --- C14: the dress, a configurable product from loly store -----------------

/// The frame's choices: Beige floral, size M (three left).
Future<void> _pickDressOptions(WidgetTester tester) async {
  await _tapScrolled(tester, find.byKey(const ValueKey('pdp-option-color-11')));
  await _tapScrolled(tester, find.byKey(const ValueKey('pdp-option-size-23')));
  _toTop(tester);
  await pumpFor(tester, 200);
}

AuditSetup _dressSetup(String locale) {
  return AuditSetup(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(
        DetailCatalog(
          withBlankPhotos(
            floralDressDetail(locale: locale, withCategory: true),
          ),
        ),
      ),
      // The product page's delivery card is made from the trust block.
      homeCmsBlocksProvider.overrideWith(
        (ref) async => {
          'hm_home_trust': locale == 'ar' ? kTrustBlockAr : kTrustBlockEn,
        },
      ),
      marketplaceAnswer(floralDressMarketplaceItem(locale: locale)),
    ],
  );
}

// --- C14: the duffle bag with two other sellers ------------------------------

AuditSetup _duffleSetup(String locale) => AuditSetup(
  overrides: [
    dufflePublicClient(),
    catalogRepositoryProvider.overrideWithValue(DuffleCatalog()),
    productRouteRepositoryProvider.overrideWithValue(DuffleRoutes()),
  ],
);

// --- C14b: bundles -----------------------------------------------------------

AuditSetup _fitnessPackSetup(String locale) {
  return AuditSetup(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(
        DetailCatalog(
          ProductDetail(
            sku: 'HM-DEMO-BUNDLE-FITNESS',
            name: locale == 'ar'
                ? 'باقة اللياقة المنزلية'
                : 'Home Fitness Starter Pack',
            urlKey: 'home-fitness-starter-pack',
            typeId: 'bundle',
            shortDescription: locale == 'ar'
                ? 'كل ما تحتاجه لبدء التمرين في المنزل — أربع أساسيات من '
                      'بائع واحد بسعر أوفر من شرائها منفصلة.'
                : 'Everything you need to start training at home — four '
                      'essentials from one seller, bundled at a saving over '
                      'buying them one by one.',
          ),
        ),
      ),
      marketplaceAnswer(fitnessPackJson()),
    ],
  );
}

AuditSetup _kitBuilderSetup(String locale) {
  return AuditSetup(
    overrides: [
      catalogRepositoryProvider.overrideWithValue(
        DetailCatalog(
          const ProductDetail(
            sku: 'KIT-BUILDER',
            name: 'Kit Builder',
            urlKey: 'kit-builder',
            typeId: 'bundle',
          ),
        ),
      ),
      marketplaceAnswer(kitBuilderJson()),
    ],
  );
}

// --- C14c: the sheet an add opens --------------------------------------------

/// The same neighbours as the Arabic store view names them (Figma 14c, Arabic).
List<Product> _sheetRecommendations(String locale) {
  final ar = locale == 'ar';
  return [
    Product(
      sku: 'TOP',
      name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
      urlKey: 'square-neck-t-shirt',
      finalPrice: const Money(amount: 43, currency: 'AED'),
    ),
    Product(
      sku: 'SHORTS',
      name: ar ? 'شورت قصير جيب جانبي' : 'Short Shorts with Flap Pocket',
      urlKey: 'flap-pocket-shorts',
      finalPrice: const Money(amount: 13, currency: 'AED'),
    ),
    Product(
      sku: 'POLO',
      name: ar ? 'تيشيرت بولو' : 'Polo Shirt',
      urlKey: 'polo-shirt',
      finalPrice: const Money(amount: 13, currency: 'AED'),
    ),
  ];
}

/// The frame's add: size M, three left, named as the store view of the
/// language does.
AddedItem _sheetItem(String locale) {
  final ar = locale == 'ar';
  return AddedItem(
    name: ar
        ? 'فستان صدر طباعة الأزهار رباط مشد خصر'
        : 'Floral Print Corset-Waist Tie Dress',
    quantity: 1,
    unitPrice: const Money(amount: 50, currency: 'AED'),
    options: ar
        ? ['المقاس: M', 'اللون: بيج مزهر']
        : ['Size: M', 'Colour: Beige floral'],
    onlyLeft: 3,
    onlyLeftOption: ar ? 'مقاس M' : 'size M',
  );
}

/// A page with a button that opens the sheet, as an add-to-cart would.
Widget _sheetOpener(String locale) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: TextButton(
        onPressed: () => AddedToCartSheet.show(
          context,
          item: _sheetItem(locale),
          recommendations: _sheetRecommendations(locale),
        ),
        child: const Text('open'),
      ),
    ),
  ),
);

// --- C15 / C15b: reviews -----------------------------------------------------

/// Figma 15 offers the per-star bars and chips only once every review is in
/// hand: 27 reviews are two pages, so scroll to the end for the second and
/// back to the top.
Future<void> _loadAllReviews(WidgetTester tester) async {
  final list = find.byType(ListView);
  await tester.drag(list, const Offset(0, -5000));
  await pumpFor(tester, 500);
  await tester.drag(list, const Offset(0, -5000));
  await pumpFor(tester, 500);
  await tester.drag(list, const Offset(0, 8000));
  await pumpFor(tester, 500);
}

/// Stores and product: C12 Stores, C13 Store (tabs: products, reviews, about, policies), C13b Store about, C14 PDP (and the other-sellers variant), C14b Bundle PDP, C14c Added to cart sheet, C15 Reviews, C15b Write review.
///
/// One scene per frame state, ported from the widget test that renders it (see
/// docs/ui-audit.md, `PAIRS` in tool/ui_audit/pairs.py names the captures):
///
/// - C12 / C13 / C13b: test/features/stores/presentation/stores_screens_render_test.dart
///   (the P3.1 renders: a server that lists the `vendors` capability), mounted
///   at the root of the router like the test does (a tab: no back arrow on the
///   list), signed out. The test's `drag` on the About and Reviews tabs is left
///   out: its 1075 / 1250 px surface held the whole tab, so it scrolled
///   nothing, and on the phone it would hide the store row the frame shows.
/// - C14 default: test/features/marketplace/marketplace_render_test.dart
///   `14 product page with "Sold by"`; C14 other_sellers: other_sellers_test.dart.
///   The product page draws its own back button, so root or pushed looks the same.
/// - C14b: marketplace_render_test.dart `14b bundle page` and `14b bundle with
///   choices`.
/// - C14c: test/features/cart/added_to_cart_sheet_test.dart `renders (Figma 14c)`:
///   a page with a button that opens the sheet, as the test does (the frame's
///   page behind the sheet is a blank block too).
/// - C15: test/features/catalog/presentation/product_reviews_render_test.dart
///   (all 27 reviews, pushed so the app bar carries its back arrow);
///   C15b: write_review_screen_test.dart `audit_15b_write_review` (pushed).
///
/// Beyond the listed captures, four states the tests render or the frames
/// imply: C13_store `reviews`, C13b_store_about `policies` (no test captures
/// it), C14_pdp `other_sellers_sheet` and C14b_bundle_pdp `choices`.
///
/// Every scene installs the offline public client (or its own answers): the
/// harness does not fake `publicGraphqlClientProvider`, and nothing here may
/// leave the app. No scene carries a photo URL (`withBlankPhotos`): the host
/// sweep cannot wait for a network image, and the phone would only ask the live
/// store for files that do not exist. The product photos are placeholder tiles.
List<AuditScene> scenes() => [
  // ---- C12 Stores: the list with the counted category chips and the
  // category line on each card (stores_12_list_p31).
  AuditScene(
    frame: 'C12_stores',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const StoresScreen(),
    setup: _storesSetup,
  ),

  // ---- C13 Store: the front page (Products tab) with Contact vendor
  // (stores_13_store_p31), and the Reviews tab (stores_13_reviews).
  AuditScene(
    frame: 'C13_store',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const StoreScreen(code: 'MIA'),
    setup: _storesSetup,
  ),
  AuditScene(
    frame: 'C13_store',
    name: 'reviews',
    pushed: false,
    signedIn: false,
    screen: (_) => const StoreScreen(code: 'MIA'),
    setup: _storesSetup,
    act: (tester, locale) =>
        _openStoreTab(tester, _l10n(locale).storeTabReviews),
  ),

  // ---- C13b Store about: the About tab with Sales and Call
  // (stores_13b_about_p31); the frame is 1075 px high.
  AuditScene(
    frame: 'C13b_store_about',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const StoreScreen(code: 'MIA'),
    setup: _storesSetup,
    act: (tester, locale) => _openStoreTab(tester, _l10n(locale).storeTabAbout),
    scrolls: 1,
  ),
  // The fourth tab: no test captures it, the phone should still see it.
  AuditScene(
    frame: 'C13b_store_about',
    name: 'policies',
    pushed: false,
    signedIn: false,
    screen: (_) => const StoreScreen(code: 'MIA'),
    setup: _storesSetup,
    act: (tester, locale) =>
        _openStoreTab(tester, _l10n(locale).storeTabPolicies),
  ),

  // ---- C14 PDP: the dress with its colour and size chosen and two other
  // sellers (p3_14_sold_by); the frame is 2379 px high.
  AuditScene(
    frame: 'C14_pdp',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) => const ProductDetailScreen(urlKey: 'floral-dress'),
    setup: _dressSetup,
    act: (tester, locale) => _pickDressOptions(tester),
    scrolls: 3,
  ),
  // The duffle bag, whose "Sold by N other sellers" card lists the offers
  // (pdp_other_sellers) ...
  AuditScene(
    frame: 'C14_pdp',
    name: 'other_sellers',
    pushed: false,
    signedIn: false,
    screen: (_) => const ProductDetailScreen(urlKey: 'joust-duffle-bag'),
    setup: _duffleSetup,
    scrolls: 1,
  ),
  // ... and its "Compare" sheet (pdp_other_sellers_sheet).
  AuditScene(
    frame: 'C14_pdp',
    name: 'other_sellers_sheet',
    pushed: false,
    signedIn: false,
    screen: (_) => const ProductDetailScreen(urlKey: 'joust-duffle-bag'),
    setup: _duffleSetup,
    act: (tester, locale) =>
        _tapScrolled(tester, find.text(_l10n(locale).pdpOtherSellersCompare)),
  ),

  // ---- C14b Bundle PDP: the fixed package (p3_14b_bundle, 1156 px high) ...
  AuditScene(
    frame: 'C14b_bundle_pdp',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: (_) =>
        const ProductDetailScreen(urlKey: 'home-fitness-starter-pack'),
    setup: _fitnessPackSetup,
    scrolls: 1,
  ),
  // ... and a bundle with choices, its list of items opened
  // (p3_14b_bundle_choices).
  AuditScene(
    frame: 'C14b_bundle_pdp',
    name: 'choices',
    pushed: false,
    signedIn: false,
    screen: (_) => const ProductDetailScreen(urlKey: 'kit-builder'),
    setup: _kitBuilderSetup,
    act: (tester, locale) async {
      await _tapScrolled(tester, find.byIcon(HubIcons.chevronDown));
      _toTop(tester);
    },
    scrolls: 1,
  ),

  // ---- C14c Added to cart: the sheet over a page, its subtotal the cart of
  // Figma 18b (4 items, AED 543) and the store counting down to its
  // free-shipping line (added_to_cart).
  AuditScene(
    frame: 'C14c_added_to_cart',
    name: 'default',
    pushed: false,
    signedIn: false,
    screen: _sheetOpener,
    setup: (locale) => AuditSetup(
      // The product page asks HubApp for its seller; Build 1 here, as in the test.
      hubApp: const HubAppState.unavailable(),
      overrides: [
        // A guest cart already exists, so the sheet's subtotal is the cart's.
        localCacheProvider.overrideWithValue(
          FakeLocalCache()..writeString('guest_cart_id', 'guest-1'),
        ),
        cartRepositoryProvider.overrideWithValue(SheetCartRepository()),
        freeShippingThresholdProvider.overrideWith((ref) async => 600),
        offlinePublicClient(),
      ],
    ),
    act: (tester, locale) async {
      await tester.tap(find.text('open'));
      await pumpFor(tester, 500);
    },
  ),

  // ---- C15 Reviews: all 27 reviews of the dress loaded, pushed from the
  // product page (15_reviews).
  AuditScene(
    frame: 'C15_reviews',
    name: 'default',
    signedIn: false,
    screen: (_) => const ProductReviewsScreen(urlKey: 'floral-dress'),
    setup: (locale) => AuditSetup(
      overrides: [
        reviewsRepositoryProvider.overrideWithValue(
          FakeReviewsRepository(
            productReviews: floralDressReviews(locale: locale),
            ratingSummary: 86,
          ),
        ),
        offlinePublicClient(),
      ],
    ),
    act: (tester, locale) => _loadAllReviews(tester),
  ),

  // ---- C15b Write review: the form filled in as the frame shows it, four
  // stars lit (audit_15b_write_review, 1110 px high).
  AuditScene(
    frame: 'C15b_write_review',
    name: 'default',
    signedIn: false,
    screen: (locale) => WriteReviewScreen(
      sku: 'LOLY-DR-0231',
      subject: dressReviewSubject(locale),
    ),
    setup: (locale) => AuditSetup(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(ReviewFormCatalog()),
        offlinePublicClient(),
      ],
    ),
    act: (tester, locale) async {
      final (nickname, summary, text) = kReviewFormText[locale]!;
      Finder field(int index) => find.byType(TextField).at(index);
      await tester.tap(find.byKey(const ValueKey('review-star-4')));
      await tester.enterText(field(0), nickname);
      await tester.enterText(field(1), summary);
      await tester.enterText(field(2), text);
      await pumpFor(tester, 300);
      // Typing is done: the caret out of the capture.
      FocusManager.instance.primaryFocus?.unfocus();
      await pumpFor(tester, 300);
    },
    scrolls: 1,
  ),
];
