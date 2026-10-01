import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/presentation/widgets/pdp_sections.dart';
import 'package:hubmarket_app/features/marketplace/presentation/other_sellers.dart';
import 'package:hubmarket_app/features/marketplace/presentation/seller_widgets.dart';

import '../../support/bundle_fixtures.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/marketplace_fakes.dart';
import '../../support/pdp_fixtures.dart';
import '../../support/store_credit_fakes.dart';
import '../checkout/checkout_harness.dart' as checkout;
import 'marketplace_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

/// Renders the P3 marketplace screens in English and Arabic to
/// build/test_screens/ for comparison with Figma 14 (16:970 / 56:2527), 14b
/// (61:2674 / 68:2864), 16 (62:2639 / 69:2829), 18b (63:2785 / 70:2978) and
/// 22 (21:1376 / 52:2104). Assertions only guard against layout errors and
/// a wrong text direction.

/// Store and product names as each store view serves them.
({String loly, String mia, String dress, String sofa, String chair}) _names(
  String locale,
) => locale == 'ar'
    ? (
        loly: 'متجر لولي',
        mia: 'ميا كو',
        dress: 'فستان صدر طباعة الأزهار رباط مشد خصر',
        sofa: 'كنبة سرير ركنه',
        chair: 'كرسي طعام بارجل ذهبية معدنية',
      )
    : (
        loly: 'loly store',
        mia: 'MIA CO',
        dress: 'Floral Print Corset-Waist Tie Dress',
        sofa: 'Corner Sofa Bed',
        chair: 'Dining Chair with Gold Metal Legs',
      );

Cart _cart(String locale, String id, {CartTotals? totals}) {
  final n = _names(locale);
  final base = twoStoreCart(id);
  final names = {'SOFA': n.sofa, 'CHAIR': n.chair, 'DRESS': n.dress};
  final sellers = {
    'SOFA': seller('mia', n.mia),
    'CHAIR': seller('mia', n.mia),
    'DRESS': seller('loly', n.loly),
  };
  return Cart(
    id: base.id,
    totalQuantity: base.totalQuantity,
    totals: totals ?? base.totals,
    items: [
      for (final item in base.items)
        CartItem(
          uid: item.uid,
          sku: item.sku,
          name: names[item.sku]!,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          originalUnitPrice: item.originalUnitPrice,
          rowTotal: item.rowTotal,
          options: item.options,
          seller: sellers[item.sku],
        ),
    ],
  );
}

/// The trust block as the frame's ticks read (titles only).
String _cartTrust(String locale) => locale == 'ar'
    ? '<div class="hm-trust">'
          '<div class="hm-trust__item"><span class="hm-trust__title">دفع آمن بتشفير SSL</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">طلبات من عدة بائعين في عملية دفع واحدة</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">إرجاع خلال 14 يومًا لمعظم المنتجات</span></div>'
          '</div>'
    : '<div class="hm-trust">'
          '<div class="hm-trust__item"><span class="hm-trust__title">Secure checkout with SSL encryption</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">Orders from multiple vendors in one checkout</span></div>'
          '<div class="hm-trust__item"><span class="hm-trust__title">14-day returns on most items</span></div>'
          '</div>';

CustomerOrder _order(String locale) {
  final n = _names(locale);
  final base = twoStoreOrder();
  return CustomerOrder(
    number: base.number,
    status: base.status,
    date: base.date,
    id: base.id,
    total: base.total,
    subtotal: base.subtotal,
    shippingAmount: base.shippingAmount,
    paymentMethodName: base.paymentMethodName,
    lines: [
      OrderLine(
        name: n.dress,
        quantity: 1,
        price: aed(50),
        sku: 'DRESS',
        seller: seller('loly', n.loly),
      ),
      OrderLine(
        name: n.sofa,
        quantity: 1,
        price: aed(425),
        sku: 'SOFA',
        seller: seller('mia', n.mia),
      ),
      OrderLine(
        name: n.chair,
        quantity: 2,
        price: aed(34),
        sku: 'CHAIR',
        seller: seller('mia', n.mia),
      ),
    ],
  );
}

/// The checkout's cart with each line's store.
class _SellerCheckoutCart extends checkout.CheckoutCartRepository {
  _SellerCheckoutCart(this.locale);
  final String locale;

  @override
  Future<Cart> getCart(String cartId) async => _cart(locale, cartId);
}

void main() {
  setUpAll(loadAppFonts);
  quietNetworkImages();

  Future<void> render(
    WidgetTester tester,
    Widget Function(GlobalKey key) app,
    String name, {
    required double height,
    required String locale,
    Future<void> Function()? before,
  }) async {
    phoneView(tester, height: height);
    final key = GlobalKey();
    await withRealShadows(() async {
      await tester.pumpWidget(app(key));
      await tester.pumpAndSettle();
      if (before != null) await before();
      // Without captureScreen's image pre-cache: catalogue images are
      // network images, which never load in a widget test.
      await checkout.capture(tester, key, name);
    });
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).first)),
      locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
    );
  }

  for (final locale in ['en', 'ar']) {
    final n = _names(locale);

    testWidgets('14 product page with "Sold by" ($locale)', (tester) async {
      // The whole of Figma 14 (390 x 2379, the buy bar at the foot): the
      // dress in Beige floral, size M — three left — with two other sellers.
      await render(
        tester,
        (key) => marketplaceHarness(
          locale: locale,
          location: AppRoutes.product('floral-dress'),
          boundary: key,
          catalogRepository: DetailRepository(
            floralDressDetail(locale: locale, withCategory: true),
          ),
          cmsBlocks: {
            'hm_home_trust': locale == 'ar' ? kTrustBlockAr : kTrustBlockEn,
          },
          publicAnswers: {
            'HmProductMarketplace': {
              'products': {
                'items': [floralDressMarketplaceItem(locale: locale)],
              },
            },
          },
        ),
        'p3_14_sold_by_$locale',
        height: locale == 'ar' ? 2479 : 2379,
        locale: locale,
        before: () async {
          await tester.tap(find.byKey(const ValueKey('pdp-option-color-11')));
          await tester.tap(find.byKey(const ValueKey('pdp-option-size-23')));
          await tester.pumpAndSettle();
          // The blocks have the heights of the frame (English; 14 px apart).
          double height(Finder f, [int index = 0]) =>
              tester.getRect(f.at(index)).height;
          if (locale == 'en') {
            expect(height(find.byType(SoldByRow)), 48);
            expect(height(find.byType(PdpPriceRow)), 30);
            expect(height(find.byType(PdpOptionPicker), 0), 64);
            expect(height(find.byType(PdpOptionPicker), 1), 68);
            expect(height(find.byType(OtherSellersCard)), 170);
            expect(height(find.byType(OfferTile)), 59);
            expect(height(find.byType(PdpAccordion), 0), 51);
            expect(height(find.byType(PdpAccordion), 1), 177);
            expect(height(find.byType(PdpReviewsSection)), 276);
          }
        },
      );
      expect(
        find.descendant(
          of: find.byType(SoldByRow),
          matching: find.text(n.loly),
        ),
        findsOneWidget,
      );
    });

    testWidgets('14b bundle page ($locale)', (tester) async {
      await render(
        tester,
        (key) => marketplaceHarness(
          locale: locale,
          location: AppRoutes.product('home-fitness-starter-pack'),
          boundary: key,
          catalogRepository: DetailRepository(
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
          publicAnswers: {
            'HmProductMarketplace': {
              'products': {
                'items': [fitnessPackJson()],
              },
            },
          },
        ),
        'p3_14b_bundle_$locale',
        height: locale == 'ar' ? 1180 : 1156,
        locale: locale,
        before: () async {
          // The frame's offsets (English): the title, the package card's
          // heading and the summary's, top to bottom.
          if (locale == 'en') {
            double top(String text) => tester.getTopLeft(find.text(text)).dy;
            expect(top('Home Fitness Starter Pack'), 338);
            expect(top('Items in this package'), 497);
            expect(top('Package summary'), 862);
          }
        },
      );
    });

    testWidgets('14b bundle with choices ($locale)', (tester) async {
      await render(
        tester,
        (key) => marketplaceHarness(
          locale: locale,
          location: AppRoutes.product('kit-builder'),
          boundary: key,
          catalogRepository: DetailRepository(
            const ProductDetail(
              sku: 'KIT-BUILDER',
              name: 'Kit Builder',
              urlKey: 'kit-builder',
              typeId: 'bundle',
            ),
          ),
          publicAnswers: {
            'HmProductMarketplace': {
              'products': {
                'items': [kitBuilderJson()],
              },
            },
          },
        ),
        'p3_14b_bundle_choices_$locale',
        height: 1400,
        locale: locale,
        before: () async {
          await tester.tap(find.byIcon(HubIcons.chevronDown));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('16 cart by store ($locale)', (tester) async {
      await render(
        tester,
        (key) => marketplaceHarness(
          locale: locale,
          location: AppRoutes.cart,
          boundary: key,
          cartRepository: CannedCartRepository(_cart(locale, 'guest-1')),
          // The frame's free-shipping bar needs the store's threshold, and
          // its ticks come from the storefront's trust block.
          freeShipping: 600,
          cmsBlocks: {'hm_home_trust': _cartTrust(locale)},
        ),
        'p3_16_cart_$locale',
        // The frame (1310 / 1334 tall) plus the 6 px its tab bar lacks under
        // the iPhone's 34 px home-indicator inset.
        height: locale == 'ar' ? 1340 : 1316,
        locale: locale,
      );
      expect(find.text(n.mia), findsOneWidget);
    });

    testWidgets('16 cart with store credit used ($locale)', (tester) async {
      await render(
        tester,
        (key) => marketplaceHarness(
          locale: locale,
          location: AppRoutes.cart,
          boundary: key,
          hubApp: HubAppState.available(hubAppAccountConfig(storeCredit: true)),
          signedIn: true,
          storeCredit: FakeStoreCreditRepository(
            cartCredit: sampleCartCredit(applied: 50),
          ),
          // What the server answers once credit is used: 543 + 10 − 50.
          cartRepository: CannedCartRepository(
            _cart(
              locale,
              'customer-1',
              totals: CartTotals(
                subtotal: aed(543),
                shipping: aed(10),
                grandTotal: aed(503),
              ),
            ),
          ),
        ),
        'p3_16_cart_credit_$locale',
        height: 1400,
        locale: locale,
      );
      // The summary adds up: the delivery fee chosen at checkout is shown.
      expect(find.text('AED 10'), findsOneWidget);
      // The summary's total and the pinned bar's.
      expect(find.text('AED 503'), findsNWidgets(2));
    });

    testWidgets('18b review by store ($locale)', (tester) async {
      tester.view.physicalSize = const Size(390, 1250);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        checkout.checkoutHarness(
          locale: locale,
          repository: checkout.checkoutRepository(),
          signedIn: true,
          boundary: key,
          cartRepository: _SellerCheckoutCart(locale),
        ),
      );
      await tester.pumpAndSettle();
      final en = locale == 'en';
      await checkout.tapText(
        tester,
        en ? 'Continue to payment' : 'المتابعة للدفع',
      );
      await checkout.tapText(tester, en ? 'Review order' : 'مراجعة الطلب');
      await checkout.capture(tester, key, 'p3_18b_review_$locale');
      expect(find.text(n.mia), findsOneWidget);
      expect(find.text(n.loly), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('22 order by store ($locale)', (tester) async {
      await render(
        tester,
        (key) => marketplaceHarness(
          locale: locale,
          location: AppRoutes.orderDetail,
          boundary: key,
          order: _order(locale),
          hubApp: const HubAppState.available(kSampleHmAppConfig),
        ),
        'p3_22_order_$locale',
        height: 1500,
        locale: locale,
      );
    });
  }
}
