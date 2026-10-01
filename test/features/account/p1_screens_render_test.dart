import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/my_reviews_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/privacy_data_screen.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/catalog/presentation/screens/product_reviews_screen.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/cms_page.dart';
import 'package:hubmarket_app/features/cms/presentation/cms_page_screen.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_screen.dart';
import 'package:hubmarket_app/features/wishlist/data/wishlist_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/hubapp_fakes.dart';

/// Renders the P1 stream-B screens — Figma 15, 20f, 21b, 20h, 27, 28 and 20b (the
/// Account ones as `p1_NAME`: the audit captures are in account_subpages_audit_test)
/// — in English and Arabic to `build/test_screens/` for comparison with the
/// frames (build/ is gitignored; nothing is asserted on the images). Each
/// render also fails on any layout exception, so it doubles as an RTL and
/// overflow smoke test.

Future<void> _loadFonts() => loadAppFonts();

ProductReview _review(String name, int stars, String title, String text) =>
    ProductReview(
      nickname: name,
      summary: title,
      text: text,
      averageRating: stars * 20,
      date: '2026-09-12 10:24:33',
    );

List<ProductReview> _reviews(bool ar) => ar
    ? [
        _review('نور أ.', 5, 'قماش جميل', 'قماش جميل والمقاس مضبوط. رباط الخصر يعطي شكلًا رائعًا. وصل خلال يومين.'),
        _review('ريم ك.', 3, 'الطول أقصر', 'الطبعة جميلة لكن الطول أقصر مما توقعت لمقاس M.'),
        _review('سارة م.', 5, 'رائع', 'مريح جدًا ومناسب للصيف.'),
        _review('هند ع.', 4, 'جيد', 'اللون مطابق للصورة.'),
      ]
    : [
        _review('Nour A.', 5, 'Lovely fabric', 'Beautiful fabric and the fit is true to size. The tie waist is very flattering. Arrived in 2 days.'),
        _review('Reem K.', 3, 'Shorter than expected', 'Nice print but the length was shorter than I expected for size M.'),
        _review('Sara M.', 5, 'Perfect for summer', 'Light, comfortable and exactly as pictured.'),
        _review('Hind A.', 4, 'Good value', 'The colour matches the photos.'),
      ];

List<CustomerReview> _mine(bool ar) => [
  CustomerReview(
    review: _review(
      'Sara',
      4,
      ar ? 'قماش جميل ومقاس مضبوط' : 'Lovely fabric, true to size',
      ar
          ? 'الطبعة جميلة ورباط الخصر يعطي شكلًا رائعًا. وصل خلال يومين.'
          : 'Beautiful print and the tie waist is really flattering. Arrived in two days.',
    ),
    productName: ar ? 'فستان صدر طباعة الأزهار' : 'Floral Print Corset-Waist Tie Dress',
    productUrlKey: 'floral-dress',
  ),
  CustomerReview(
    review: _review(
      'Sara',
      5,
      ar ? 'مريحة وسهلة التحويل' : 'Comfortable and easy to convert',
      ar
          ? 'وصلت وتم تركيبها في 20 دقيقة.'
          : 'Delivered and assembled in 20 minutes. The teal colour is exactly as pictured.',
    ),
    productName: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
    productUrlKey: 'corner-sofa-bed',
  ),
];

CmsPage _privacyPage(bool ar) => CmsPage(
  identifier: 'privacy-policy-cookie-restriction-mode',
  title: ar ? 'سياسة الخصوصية' : 'Privacy Policy',
  urlKey: 'privacy-policy-cookie-restriction-mode',
  content: ar
      ? '<p>توضح هذه السياسة ما يجمعه هب ماركت عند تسوقك معنا، ولماذا، والخيارات المتاحة لك.</p>'
            '<h2 id="a">ما نجمعه</h2><p>اسمك وبيانات التواصل وعناوين التوصيل؛ وطلباتك وتقييماتك.</p>'
            '<h2 id="b">كيف نستخدمه</h2><ul><li>لتوصيل طلباتك.</li><li>لمشاركة بيانات التوصيل التي يحتاجها كل متجر.</li></ul>'
            '<h2 id="c">خياراتك</h2><p>احذف حسابك في أي وقت من <a href="#a">الخصوصية والبيانات</a>.</p>'
            '<h2 id="d">ملفات الارتباط</h2><table><tr><th>الملف</th><th>الاستخدام</th></tr><tr><td>CART</td><td>سلتك</td></tr></table>'
      : '<p>This policy explains what Hub Market collects when you shop with us, why, and the choices you have.</p>'
            '<h2 id="a">What we collect</h2><p>Your name, <strong>contact details</strong> and delivery addresses; your orders and reviews.</p>'
            '<h2 id="b">How we use it</h2><ul><li>To deliver your orders.</li><li>To share the delivery details each store needs.</li></ul>'
            '<h2 id="c">Your choices</h2><p>Delete your account at any time from <a href="#a">Privacy &amp; data</a>.</p>'
            '<h2 id="d">Cookies</h2><table><tr><th>Cookie</th><th>Use</th></tr><tr><td>CART</td><td>Your cart</td></tr></table>',
);

const _order = CustomerOrder(
  number: '000000248',
  status: 'Pending',
  date: '2026-09-28 10:42:00',
  id: 'MjQ4',
  token: 'tok-248',
  availableActions: {'CANCEL', 'REORDER'},
  invoiceCount: 1,
  total: Money(amount: 553, currency: 'AED'),
  subtotal: Money(amount: 543, currency: 'AED'),
  shippingAmount: Money(amount: 10, currency: 'AED'),
  lines: [
    OrderLine(
      name: 'Floral Print Corset-Waist Tie Dress',
      quantity: 1,
      price: Money(amount: 50, currency: 'AED'),
    ),
  ],
);

Future<void> _render(
  WidgetTester tester, {
  required String name,
  required String locale,
  required Widget screen,
  double height = 844,
  bool signedIn = true,
  bool push = false,
  FakeCmsRepository? cms,
  FakeReviewsRepository? reviews,
  Future<void> Function(WidgetTester tester)? then,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final boundary = GlobalKey();
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.help,
        AppRoutes.signIn,
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
      secureTokenStoreProvider.overrideWithValue(
        FakeSecureTokenStore(signedIn ? 'persisted' : null),
      ),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(customer: kSampleCustomer),
      ),
      graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      wishlistRepositoryProvider.overrideWithValue(FakeWishlistRepository()),
      accountRepositoryProvider.overrideWithValue(FakeAccountRepository()),
      cmsRepositoryProvider.overrideWithValue(
        cms ??
            FakeCmsRepository(
              blocks: {
                'hm_footer_legal': locale == 'ar'
                    ? kLegalLinksBlock
                          .replaceAll('>Privacy<', '>الخصوصية<')
                          .replaceAll('>Terms<', '>الشروط<')
                          .replaceAll('>Cookies<', '>ملفات الارتباط<')
                    : kLegalLinksBlock,
              },
            ),
      ),
      reviewsRepositoryProvider.overrideWithValue(
        reviews ?? FakeReviewsRepository(),
      ),
      storeFeaturesProvider.overrideWith(
        (ref) async => const StoreFeatures(
          orderCancellationEnabled: true,
          cancellationReasons: [
            'The item(s) are no longer needed',
            'The order was placed by mistake',
            'Item(s) not arriving within the expected timeframe',
            'Found a better price elsewhere',
            'Other',
          ],
          newsletterEnabled: true,
          contactEnabled: true,
        ),
      ),
      storeContactProvider.overrideWithValue(
        const StoreContact(
          website: 'https://hub-market.magento2.click',
          whatsapp: 'https://wa.me/13156360140',
        ),
      ),
      storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
      appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
      pushNotificationsAvailableProvider.overrideWithValue(push),
      // Build 1: no Hub Market App; the P1 frames predate store credit and
      // returns.
      hubAppOverride(const HubAppState.unavailable()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: boundary,
        child: MaterialApp.router(
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
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (then != null) await then(tester);
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/${name}_$locale.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);

  for (final locale in const ['en', 'ar']) {
    final ar = locale == 'ar';

    testWidgets('15 Reviews ($locale)', (tester) async {
      await _render(
        tester,
        name: '15_reviews',
        locale: locale,
        screen: const ProductReviewsScreen(urlKey: 'floral-dress'),
        reviews: FakeReviewsRepository(
          productReviews: _reviews(ar),
          ratingSummary: 86,
        ),
      );
    });

    testWidgets('20f My product reviews ($locale)', (tester) async {
      await _render(
        tester,
        name: 'p1_20f_my_reviews',
        locale: locale,
        screen: const MyReviewsScreen(),
        reviews: FakeReviewsRepository(customerReviews: _mine(ar)),
      );
    });

    testWidgets('21b Cancel order ($locale)', (tester) async {
      await _render(
        tester,
        name: '21b_cancel_order',
        locale: locale,
        screen: const OrderDetailScreen(order: _order),
        then: (tester) async {
          final l10n = lookupAppLocalizations(Locale(locale));
          await tester.ensureVisible(find.text(l10n.orderCancelAction));
          await tester.tap(find.text(l10n.orderCancelAction));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('22 Order detail cancel section ($locale)', (tester) async {
      await _render(
        tester,
        name: '22_order_detail_cancel',
        locale: locale,
        height: 1200,
        screen: const OrderDetailScreen(order: _order),
      );
    });

    testWidgets('20h Notification settings ($locale)', (tester) async {
      await _render(
        tester,
        name: 'p1_20h_notification_settings',
        locale: locale,
        push: true,
        screen: const NotificationSettingsScreen(),
      );
    });

    testWidgets('27 Help centre ($locale)', (tester) async {
      await _render(
        tester,
        name: 'p1_27_help_centre',
        locale: locale,
        height: 1560,
        screen: const HelpScreen(),
      );
    });

    testWidgets('28 Content page ($locale)', (tester) async {
      await _render(
        tester,
        name: 'p1_28_content_page',
        locale: locale,
        screen: const CmsPageScreen(
          url: 'privacy-policy-cookie-restriction-mode',
        ),
        cms: FakeCmsRepository(
          pagesByUrl: {'privacy-policy-cookie-restriction-mode': _privacyPage(ar)},
        ),
      );
    });

    testWidgets('20b Privacy & data ($locale)', (tester) async {
      await _render(
        tester,
        name: 'p1_20b_privacy_data',
        locale: locale,
        screen: const PrivacyDataScreen(),
      );
    });
  }
}
