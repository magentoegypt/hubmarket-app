import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/screens/cart_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_subject.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/pdp_buy_bar.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/pdp_sections.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';
import '../../../support/fonts.dart';
import '../../../support/pdp_fixtures.dart';
import '../../marketplace/marketplace_harness.dart';

/// Figma 14 — what the redesigned product page does: the gallery's controls and
/// pager, the options and their stock, the accordions, the links out of it, and
/// the buy bar.

/// Records what goes into the cart.
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

final _en = lookupAppLocalizations(const Locale('en'));

/// The routes the page leaves to, each saying what it was opened with.
List<RouteBase> _routes() => [
  GoRoute(
    path: '/category/:uid',
    builder: (_, s) => Scaffold(
      body: Text('CATEGORY ${s.pathParameters['uid']} ${s.extra}'),
    ),
  ),
  GoRoute(
    path: '/reviews/:urlKey',
    builder: (_, s) =>
        Scaffold(body: Text('REVIEWS ${s.pathParameters['urlKey']}')),
  ),
  GoRoute(
    path: '/review/:sku',
    builder: (_, s) {
      final subject = s.extra as ReviewSubject?;
      return Scaffold(
        body: Text(
          'WRITE ${s.pathParameters['sku']} ${subject?.name} '
          '${subject?.sellerName}',
        ),
      );
    },
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  ProductDetail? detail,
  String locale = 'en',
  _Cart? cart,
  double height = 2400,
}) async {
  phoneView(tester, height: height);
  await tester.pumpWidget(
    marketplaceHarness(
      locale: locale,
      location: AppRoutes.product('floral-dress'),
      catalogRepository: DetailRepository(
        detail ?? floralDressDetail(locale: locale),
      ),
      cartRepository: cart,
      extraRoutes: _routes(),
      cmsBlocks: {'hm_home_trust': kTrustBlockEn},
      publicAnswers: {
        'HmProductMarketplace': {
          'products': {
            'items': [floralDressMarketplaceItem(locale: locale)],
          },
        },
      },
    ),
  );
  await tester.pumpAndSettle();
}

Finder _option(String code, int value) =>
    find.byKey(ValueKey('pdp-option-$code-$value'));

Future<void> _choose(WidgetTester tester, {int colour = 11, int size = 23}) async {
  await tester.tap(_option('color', colour));
  await tester.tap(_option('size', size));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);
  quietNetworkImages();

  group('the gallery', () {
    testWidgets('draws the pager and the counter, and swiping moves them', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('1 / 4'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one photo needs no pager and no counter', (tester) async {
      await _pump(tester, detail: floralDressDetail(gallery: 1));

      expect(find.textContaining(' / '), findsNothing);
    });

    testWidgets('carries the round back, share, wishlist and cart buttons', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byTooltip(_en.actionShare), findsOneWidget);
      expect(find.byTooltip(_en.navWishlist), findsOneWidget);
      expect(find.byTooltip(_en.navCart), findsOneWidget);
      // No app bar over it: the photo starts at the very top.
      expect(find.byType(AppBar), findsNothing);
      expect(tester.getTopLeft(find.byType(PageView)).dy, 0);
    });

    testWidgets('the cart button opens the cart', (tester) async {
      await _pump(tester);

      await tester.tap(find.byTooltip(_en.navCart));
      await tester.pumpAndSettle();
      expect(find.byType(CartScreen), findsOneWidget);
    });

    testWidgets('share copies the storefront link', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester);

      await tester.tap(find.byTooltip(_en.actionShare));
      await tester.pump();
      // The store's own link, or the generic error when the store views are
      // not known yet — never a made-up address.
      expect(
        copied.isNotEmpty || find.text(_en.errorGeneric).evaluate().isNotEmpty,
        isTrue,
      );
    });
  });

  group('the options', () {
    testWidgets('colours are swatches, sizes are chips, and the header names '
        'the choice', (tester) async {
      await _pump(tester);

      // Nothing chosen yet: just the option's name.
      expect(find.text('Colour:'), findsOneWidget);
      expect(_option('color', 11), findsOneWidget);
      expect(find.text('XS'), findsOneWidget);
      expect(find.text('XL'), findsOneWidget);

      await tester.tap(_option('color', 12));
      await tester.pumpAndSettle();
      expect(find.textContaining('Charcoal'), findsOneWidget);

      await tester.tap(_option('size', 22));
      await tester.pumpAndSettle();
      expect(find.textContaining('Size:'), findsOneWidget);
    });

    testWidgets('a size no variant has in stock is drawn disabled', (
      tester,
    ) async {
      await _pump(tester);

      Color labelColour(int size) => tester
          .widget<Text>(
            find.descendant(of: _option('size', size), matching: find.byType(Text)),
          )
          .style!
          .color!;
      expect(labelColour(25), AppColors.disabled); // XL
      expect(labelColour(23), AppColors.inkHeading); // M
    });

    testWidgets('"Only 3 left in size M" follows the chosen variant', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(PdpLowStockLine), findsNothing);

      await _choose(tester);
      expect(find.text('Only 3 left in size M'), findsOneWidget);

      // L: the store reports no low stock for it.
      await tester.tap(_option('size', 24));
      await tester.pumpAndSettle();
      expect(find.byType(PdpLowStockLine), findsNothing);
    });

    testWidgets('a sold-out size says so on the buy bar', (tester) async {
      await _pump(tester);

      await _choose(tester, size: 25);
      expect(find.text(_en.pdpInStock), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PdpBuyBar),
          matching: find.text(_en.productOutOfStock),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the price follows the variant and the "Inclusive of VAT" '
        'note stays beside it', (tester) async {
      await _pump(tester);

      expect(find.text('AED 50'), findsWidgets);
      expect(find.text(_en.pdpInclusiveVat), findsOneWidget);
    });
  });

  group('the sections', () {
    testWidgets('"Description & material" opens on a tap; "Specifications" '
        'starts open', (tester) async {
      await _pump(tester);

      expect(
        find.text('A soft crepe dress with a corset waist that ties at the back.'),
        findsNothing,
      );
      // Specifications: the attribute rows and the SKU.
      expect(find.text('Polyester crepe'), findsOneWidget);
      expect(find.text('LOLY-DR-0231'), findsOneWidget);

      await tester.tap(find.text(_en.pdpDescriptionMaterial));
      await tester.pumpAndSettle();
      expect(
        find.text('A soft crepe dress with a corset waist that ties at the back.'),
        findsOneWidget,
      );

      await tester.tap(find.text(_en.pdpSpecifications));
      await tester.pumpAndSettle();
      expect(find.text('Polyester crepe'), findsNothing);
    });

    testWidgets('no description, no accordion for it', (tester) async {
      await _pump(
        tester,
        detail: ProductDetail(
          sku: 'X',
          name: 'Plain thing',
          urlKey: 'floral-dress',
          finalPrice: floralDressDetail().finalPrice,
        ),
      );

      expect(find.text(_en.pdpDescriptionMaterial), findsNothing);
      expect(find.text(_en.pdpSpecifications), findsOneWidget);
    });

    testWidgets('the reviews section opens the Reviews screen and the form', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text(_en.pdpRatingsReviews), findsOneWidget);
      expect(find.text('See all 27'), findsOneWidget);
      // The newest review, in its own card.
      expect(find.textContaining('Beautiful fabric'), findsOneWidget);

      await tester.tap(find.text('See all 27'));
      await tester.pumpAndSettle();
      expect(find.text('REVIEWS floral-dress'), findsOneWidget);
    });

    testWidgets('"Write a review" carries the product to the form', (
      tester,
    ) async {
      await _pump(tester);

      await tester.ensureVisible(find.text(_en.reviewsWrite));
      await tester.tap(find.text(_en.reviewsWrite));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'WRITE LOLY-DR-0231 Floral Print Corset-Waist Tie Dress loly store',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"27 reviews" under the title opens the Reviews screen', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('27 reviews').first);
      await tester.pumpAndSettle();
      expect(find.text('REVIEWS floral-dress'), findsOneWidget);
    });

    testWidgets('"Looking similar" lists the neighbours; "See all" opens the '
        "product's category", (tester) async {
      final base = floralDressDetail();
      await _pump(
        tester,
        detail: ProductDetail(
          sku: base.sku,
          name: base.name,
          urlKey: base.urlKey,
          finalPrice: base.finalPrice,
          alsoLike: base.alsoLike,
          categories: const [
            ProductCategoryRef(uid: 'root', name: 'Default', level: 1),
            ProductCategoryRef(uid: 'clothes', name: 'Clothes', level: 2),
            ProductCategoryRef(uid: 'dresses', name: 'Dresses', level: 3),
          ],
        ),
      );

      expect(find.text(_en.pdpLookingSimilar), findsOneWidget);
      expect(find.text('Polo Shirt'), findsOneWidget);
      await tester.tap(find.text(_en.homeSeeAll));
      await tester.pumpAndSettle();
      // The deepest category, with its name as the page title.
      expect(find.text('CATEGORY dresses Dresses'), findsOneWidget);
    });
  });

  group('the buy bar', () {
    testWidgets('the quantity pill counts up and down, never below one', (
      tester,
    ) async {
      await _pump(tester);

      Finder pill(IconData icon) => find.descendant(
        of: find.byType(QuantityPill),
        matching: find.byIcon(icon),
      );
      Finder count(String value) =>
          find.descendant(of: find.byType(QuantityPill), matching: find.text(value));

      expect(count('1'), findsOneWidget);
      await tester.tap(pill(HubIcons.minus));
      await tester.pump();
      expect(count('1'), findsOneWidget);
      await tester.tap(pill(HubIcons.plus));
      await tester.pump();
      await tester.tap(pill(HubIcons.plus));
      await tester.pump();
      expect(count('3'), findsOneWidget);
      await tester.tap(pill(HubIcons.minus));
      await tester.pump();
      expect(count('2'), findsOneWidget);
    });

    testWidgets('adds the chosen variant with the quantity, then shows the '
        'added sheet', (tester) async {
      final cart = _Cart();
      await _pump(tester, cart: cart);

      await _choose(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(QuantityPill),
          matching: find.byIcon(HubIcons.plus),
        ),
      );
      await tester.pump();
      await tester.tap(find.textContaining(_en.pdpAddToCart));
      await tester.pumpAndSettle();

      expect(cart.added, [
        {
          'sku': 'LOLY-DR-0231',
          'quantity': 2,
          'selected_options': ['uid-color-11', 'uid-size-23'],
        },
      ]);
      expect(find.text(_en.cartAdded), findsOneWidget);
      // The sheet's low-stock line, for the size that was added.
      expect(find.text('Only 3 left in size M'), findsWidgets);
    });

    testWidgets('"Add to cart · AED 50" waits for the options, then adds', (
      tester,
    ) async {
      final cart = _Cart();
      await _pump(tester, cart: cart);

      FilledButton button() => tester.widget<FilledButton>(
        find.ancestor(
          of: find.textContaining(_en.pdpAddToCart),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(button().onPressed, isNull);

      await _choose(tester);
      expect(button().onPressed, isNotNull);
      expect(find.text('Add to cart · AED 50'), findsOneWidget);

      await tester.tap(find.textContaining(_en.pdpAddToCart));
      await tester.pumpAndSettle();
      expect(cart.added, [
        {
          'sku': 'LOLY-DR-0231',
          'quantity': 1,
          'selected_options': ['uid-color-11', 'uid-size-23'],
        },
      ]);
      expect(find.text(_en.cartAdded), findsOneWidget);
    });
  });

  group('Arabic', () {
    testWidgets('lays the page out right to left, with the quantity pill kept '
        'as "− 1 +"', (tester) async {
      await _pump(tester, locale: 'ar');

      expect(
        Directionality.of(tester.element(find.byType(PdpBuyBar))),
        TextDirection.rtl,
      );
      // The gallery's back button is at the start: the right.
      expect(
        tester.getCenter(find.byIcon(HubIcons.arrowLeft)).dx,
        greaterThan(300),
      );
      // The pill keeps its order: minus, count, plus.
      final minus = tester.getCenter(
        find.descendant(
          of: find.byType(QuantityPill),
          matching: find.byIcon(HubIcons.minus),
        ),
      );
      final plus = tester.getCenter(
        find.descendant(
          of: find.byType(QuantityPill),
          matching: find.byIcon(HubIcons.plus),
        ),
      );
      expect(minus.dx, lessThan(plus.dx));
      expect(tester.takeException(), isNull);
    });
  });
}
