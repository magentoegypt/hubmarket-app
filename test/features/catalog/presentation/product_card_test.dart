import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/widgets/network_image.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/product_card.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../../support/fakes.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: [
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        ...overrides,
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Center(child: SizedBox(width: 180, child: child)),
        ),
      ),
    );

void main() {
  testWidgets(
    'shows name, sale price, struck regular price and discount badge',
    (tester) async {
      await tester.pumpWidget(
        _wrap(ProductCard(product: kSampleProducts.first)),
      );
      await tester.pump();

      // Per Figma, the card shows the product name (brand folded in) with no
      // separate brand line, the stacked sale/struck price, and the discount.
      expect(find.text('Coco Mademoiselle EDP'), findsOneWidget);
      expect(find.text('AED 199.00'), findsOneWidget);
      expect(find.text('AED 250.00'), findsOneWidget);
      expect(find.text('-20%'), findsOneWidget);
    },
  );

  testWidgets('full-price product shows no discount badge', (tester) async {
    await tester.pumpWidget(_wrap(ProductCard(product: kSampleProducts[1])));
    await tester.pump();

    expect(find.text('AED 300.00'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('renders the NEW badge for a product inside its new window', (
    tester,
  ) async {
    const product = Product(
      sku: 'NEW1',
      name: 'Fresh Arrival',
      urlKey: 'fresh-arrival',
      regularPrice: Money(amount: 100, currency: 'AED'),
      finalPrice: Money(amount: 100, currency: 'AED'),
      badge: ProductBadge.isNew,
    );
    await tester.pumpWidget(_wrap(const ProductCard(product: product)));
    await tester.pump();

    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('BESTSELLER'), findsNothing);
  });

  testWidgets('a configurable\'s "+" opens its page instead of adding', (
    tester,
  ) async {
    var opened = 0;
    const product = Product(
      sku: 'sofabed123',
      name: 'Corner Sofa Bed',
      urlKey: 'sofabed123',
      regularPrice: Money(amount: 500, currency: 'AED'),
      finalPrice: Money(amount: 425, currency: 'AED'),
      typeId: 'configurable',
    );
    await tester.pumpWidget(
      _wrap(ProductCard(product: product, onTap: () => opened++)),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Add to Cart'));
    await tester.pump();

    expect(opened, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  for (final type in const ['bundle', 'new_bundle']) {
    testWidgets('a $type\'s "+" opens its page and never calls the cart', (
      tester,
    ) async {
      var opened = 0;
      final cart = FakeCartRepository();
      final product = Product(
        sku: 'HM-DEMO-BUNDLE-FITNESS',
        name: 'Home Fitness Starter Pack',
        urlKey: 'home-fitness-starter-pack',
        regularPrice: const Money(amount: 72, currency: 'AED'),
        finalPrice: const Money(amount: 61, currency: 'AED'),
        typeId: type,
      );
      await tester.pumpWidget(
        _wrap(
          ProductCard(product: product, onTap: () => opened++),
          overrides: [cartRepositoryProvider.overrideWithValue(cart)],
        ),
      );
      await tester.pump();

      await tester.tap(find.byTooltip('Add to Cart'));
      await tester.pump();

      expect(opened, 1);
      // No cart was created, so nothing was sent to Magento.
      expect(cart.createCalls, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  group('rating (Figma v3 card)', () {
    Product rated({double? summary, int? count}) => Product(
      sku: 'SPRITE-KIT',
      name: 'Sprite Yoga Companion Kit',
      urlKey: 'sprite-yoga-companion-kit',
      regularPrice: const Money(amount: 77, currency: 'AED'),
      finalPrice: const Money(amount: 77, currency: 'AED'),
      ratingSummary: summary,
      reviewCount: count,
    );

    testWidgets('the average and the review count under the name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(ProductCard(product: rated(summary: 94, count: 3))),
      );
      await tester.pump();

      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('(3)'), findsOneWidget);
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
      // Read out as a sentence, not "star 4.7 (3)" (the card may merge it
      // with the name and price).
      expect(
        find.bySemanticsLabel(RegExp(r'Rated 4\.7 out of 5, from 3 reviews')),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('an average without a count (Algolia) shows the stars alone', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(ProductCard(product: rated(summary: 90))));
      await tester.pump();

      expect(find.text('4.5'), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
    });

    testWidgets('no reviews, or a listing without the fields: no stars', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              Expanded(child: ProductCard(product: rated(summary: 0, count: 0))),
              Expanded(child: ProductCard(product: rated())),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });
  });

  group('the seller line (Figma v3)', () {
    Product sold({String? seller, bool known = true}) => Product(
      sku: 'SOFA1',
      name: 'Corner Sofa Bed',
      urlKey: 'corner-sofa-bed',
      regularPrice: const Money(amount: 425, currency: 'AED'),
      finalPrice: const Money(amount: 425, currency: 'AED'),
      sellerName: seller,
      sellerCode: seller == null ? null : 'MIA',
      sellerKnown: known,
    );

    testWidgets('names the seller above the product, in link blue', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(ProductCard(product: sold(seller: 'MIA CO'))));
      await tester.pump();

      final seller = tester.widget<Text>(find.text('MIA CO'));
      expect(seller.style!.color, AppColors.info);
      expect(seller.style!.fontWeight, FontWeight.w600);
      expect(
        tester.getTopLeft(find.text('MIA CO')).dy,
        lessThan(tester.getTopLeft(find.text('Corner Sofa Bed')).dy),
      );
      // Read out as "Sold by …" (the card may merge it with the name).
      expect(find.bySemanticsLabel(RegExp('Sold by MIA CO')), findsOneWidget);
      semantics.dispose();
    });

    // The image takes what the text leaves, so its height says how tall the
    // text block is.
    Future<double> imageHeight(WidgetTester tester, Product product) async {
      await tester.pumpWidget(_wrap(ProductCard(product: product)));
      await tester.pump();
      return tester.getSize(find.byType(HubImage)).height;
    }

    testWidgets("Hub Market's own product keeps the line, empty, so rows stay level", (
      tester,
    ) async {
      final withSeller = await imageHeight(tester, sold(seller: 'MIA CO'));
      final own = await imageHeight(tester, sold());

      expect(find.text('MIA CO'), findsNothing);
      expect(own, withSeller);
    });

    testWidgets('a listing that did not ask (Build 1) has no seller line', (
      tester,
    ) async {
      final withLine = await imageHeight(tester, sold(seller: 'MIA CO'));
      final build1 = await imageHeight(
        tester,
        sold(seller: 'MIA CO', known: false),
      );

      expect(find.text('MIA CO'), findsNothing);
      expect(build1, greaterThan(withLine));
    });
  });

  // The mapper never produces BESTSELLER on Hub Market (no backing attribute);
  // the card keeps rendering it so the enum value stays usable.
  testWidgets('renders the BESTSELLER merchandising badge when flagged', (
    tester,
  ) async {
    const product = Product(
      sku: 'BS1',
      name: 'Bestselling Serum',
      urlKey: 'bestselling-serum',
      regularPrice: Money(amount: 100, currency: 'AED'),
      finalPrice: Money(amount: 100, currency: 'AED'),
      badge: ProductBadge.bestseller,
    );
    await tester.pumpWidget(_wrap(const ProductCard(product: product)));
    await tester.pump();

    expect(find.text('BESTSELLER'), findsOneWidget);
  });
}
