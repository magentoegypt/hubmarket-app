import 'package:flutter/material.dart' show Locale, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/widgets/hub_switch.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/account/domain/profile_extras.dart';
import 'package:hubmarket_app/features/account/presentation/account_overview.dart';
import 'package:hubmarket_app/features/account/presentation/account_screen.dart';
import 'package:hubmarket_app/features/account/presentation/profile_extras_provider.dart';
import 'package:hubmarket_app/features/account/presentation/screens/edit_profile_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/my_reviews_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/payment_methods_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/privacy_data_screen.dart';
import 'package:hubmarket_app/features/account/presentation/widgets/contact_form_card.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_field.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/cms_page.dart';
import 'package:hubmarket_app/features/cms/presentation/cms_page_screen.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_screen.dart';
import 'package:hubmarket_app/features/notifications/presentation/notifications_screen.dart';
import 'package:hubmarket_app/features/store_credit/presentation/my_credit_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../test/support/fakes.dart';
import '../../test/support/store_credit_fakes.dart';
import 'account_fixtures.dart';
import 'audit_scene.dart';
import 'harness.dart';

/// Account: E20 Account, E20b Privacy and data, E20c Profile, E20d My credit,
/// E20e Payment methods, E20f My reviews, E20g Notifications, E20h Notification
/// settings, E27 Help centre, E28 CMS page.
///
/// One scene per frame state, ported from the widget tests that render them:
/// test/features/account/account_hub_audit_test.dart (E20),
/// account_subpages_audit_test.dart (E20b, E20c, E20e, E20f, E20g, E20h, E27,
/// E28), test/features/store_credit/my_credit_screen_test.dart (E20d) and
/// p1_screens_render_test.dart (the second E28 state). The fakes they share are
/// in account_fixtures.dart.
///
/// A widget test renders each frame on a surface as tall as the frame, so
/// everything is built; the phone is 820 dp tall and a list builds what is
/// near its viewport. An `act` that has to tap or type further down the page
/// scrolls to it first (`revealWidget`) and back to the top (`scrollToTop`),
/// so the first capture shows the screen from its top and the `__s<n>` ones
/// what is below.
List<AuditScene> scenes() => [
  // E20: the Account tab. Figma draws the customer with 7 orders (2 active),
  // 5 wishlist items, 1 open return, 2 saved addresses, AED 120 of credit, a
  // card in the vault and AED 1,284 spent over 7 orders.
  AuditScene(
    frame: 'E20_account',
    name: 'default',
    screen: (_) => const AccountScreen(),
    pushed: false,
    scrolls: 1,
    setup: (locale) => accountSetup(
      locale,
      wishlist: SeededWishlist(5),
      overrides: [
        accountOrdersOverviewProvider.overrideWith(
          (ref) async => const AccountOrdersOverview(
            activeCount: 2,
            stats: ShoppingStats(
              totalSpent: Money(amount: 1284, currency: 'AED'),
              ordersThisYear: 7,
              averageOrder: Money(amount: 183.4, currency: 'AED'),
            ),
          ),
        ),
        openReturnsCountProvider.overrideWith((ref) async => 1),
        addressesProvider.overrideWith(
          (ref) async => const [_address, _address],
        ),
        savedCardsProvider.overrideWith((ref) async => const [kVisaCard]),
      ],
    ),
  ),
  // Not in the frames (no test captures it): what a guest sees on the tab.
  AuditScene(
    frame: 'E20_account',
    name: 'signed_out',
    screen: (_) => const AccountScreen(),
    pushed: false,
    signedIn: false,
    setup: (locale) => accountSetup(locale),
  ),
  // E20b: Privacy & data. The frame draws the "I understand" box ticked.
  AuditScene(
    frame: 'E20b_privacy',
    name: 'default',
    screen: (_) => const PrivacyDataScreen(),
    setup: (locale) => accountSetup(locale, overrides: [_legalLinks(locale)]),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      final understand = find.text(l10n.deleteAccountUnderstand);
      await revealWidget(tester, understand);
      await tester.tap(understand);
      await pumpFor(tester, 400);
      scrollToTop(tester);
    },
  ),
  // E20c: Profile details, 1124 px tall. The frame draws Change password
  // open, with a ten-character password that has a letter, a digit and no
  // symbol: three bars.
  AuditScene(
    frame: 'E20c_profile',
    name: 'default',
    screen: (_) => const EditProfileScreen(),
    setup: (locale) => accountSetup(
      locale,
      overrides: [
        profileExtrasProvider.overrideWith(
          (ref) async => const ProfileExtras(
            dateOfBirth: '1994-03-12',
            emailConfirmed: true,
          ),
        ),
      ],
    ),
    act: (tester, locale) async {
      final l10n = lookupAppLocalizations(Locale(locale));
      await revealWidget(tester, find.byType(HubSwitch));
      await tester.tap(find.byType(HubSwitch));
      await pumpFor(tester, 400);
      Finder field(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(AuthField),
        ),
        matching: find.byType(TextField),
      );
      await revealWidget(tester, field(l10n.fieldCurrentPassword));
      await typeInto(tester, field(l10n.fieldCurrentPassword), 'password1');
      await typeInto(tester, field(l10n.fieldNewPassword), 'Password12');
      await typeInto(
        tester,
        field(l10n.profileConfirmNewPassword),
        'Password12',
      );
      await pumpFor(tester, 400);
      scrollToTop(tester);
    },
    scrolls: 1,
  ),
  // E20d: My credit, 761 px tall. As in the frame, the store sells AED 50, 100
  // and 250 of credit. The Hub Market App's account module (store credit
  // switched on, see kAccountHubApp) is what lets the screen show "Buy credit".
  AuditScene(
    frame: 'E20d_credit',
    name: 'default',
    screen: (_) => const MyCreditScreen(),
    setup: (locale) => accountSetup(
      locale,
      credit: FakeStoreCreditRepository(
        pages: [sampleCreditAccount(arabic: locale == 'ar')],
        topUp: sampleTopUp(),
      ),
    ),
    scrolls: 1,
  ),
  // E20e: Stored payment methods.
  AuditScene(
    frame: 'E20e_payment_methods',
    name: 'default',
    screen: (_) => const PaymentMethodsScreen(),
    setup: (locale) => accountSetup(
      locale,
      overrides: [
        savedCardsProvider.overrideWith(
          (ref) async => const [kVisaCard, kMastercard],
        ),
      ],
    ),
  ),
  // E20f: My product reviews.
  AuditScene(
    frame: 'E20f_my_reviews',
    name: 'default',
    screen: (_) => const MyReviewsScreen(),
    setup: (locale) => accountSetup(
      locale,
      overrides: [
        reviewsRepositoryProvider.overrideWithValue(
          FakeReviewsRepository(customerReviews: _myReviews(locale == 'ar')),
        ),
      ],
    ),
  ),
  // E20g: the notification feed. The inbox is a singleton the widget test
  // fills before it mounts the screen; InboxSeed fills it while the screen is
  // up and empties it afterwards.
  AuditScene(
    frame: 'E20g_notifications',
    name: 'default',
    screen: (locale) => InboxSeed(
      items: _feed(locale == 'ar'),
      child: const NotificationsScreen(),
    ),
    setup: (locale) => accountSetup(locale),
  ),
  // E20h: Notification settings. Subscribed, as the frame's ticked box says;
  // the frame draws Deals & offers off and Save ready, so the switch is
  // turned off.
  AuditScene(
    frame: 'E20h_notif_settings',
    name: 'default',
    screen: (_) => const NotificationSettingsScreen(),
    setup: (locale) => accountSetup(
      locale,
      account: FakeAccountRepository(newsletterSubscribed: true),
    ),
    act: (tester, locale) async {
      await tester.tap(find.byType(HubSwitch));
      await pumpFor(tester, 400);
    },
  ),
  // E27: Help centre, 1460 px tall. The frame draws the message filled in, and
  // the name, e-mail and phone the contact form takes from the customer —
  // which it only does when the session is restored by the time it is built.
  AuditScene(
    frame: 'E27_help',
    name: 'default',
    screen: (_) => const SessionRestored(child: HelpScreen()),
    setup: (locale) => accountSetup(
      locale,
      overrides: [
        _legalLinks(locale),
        storeContactProvider.overrideWithValue(
          const StoreContact(
            website: 'https://hub-market.magento2.click',
            whatsapp: 'https://wa.me/971501234567',
            phone: '+971501234567',
            phoneDisplay: '+971 50 123 4567',
            email: 'care@hub.ae',
            hours: '24/7',
          ),
        ),
        // The frame's footer says "version 1.0.0"; the audit harness's own
        // "1.0.0 (1)" is what the real app prints, so only this frame is set.
        appVersionProvider.overrideWith((ref) async => '1.0.0'),
      ],
    ),
    act: (tester, locale) async {
      await revealWidget(tester, find.byType(ContactFormCard));
      await typeInto(
        tester,
        find.byType(TextField).last,
        locale == 'ar'
            ? 'الطرد الثاني من متجر ميا لم يتحرك منذ الاثنين — الطلب HM-100248.'
            : 'My second package from MIA CO hasn’t moved since Monday — order HM-100248.',
      );
      await pumpFor(tester, 400);
      scrollToTop(tester);
    },
    scrolls: 2,
  ),
  // E28: a CMS page drawn from its HTML, the privacy policy of the frame.
  AuditScene(
    frame: 'E28_cms_page',
    name: 'default',
    screen: (_) =>
        const CmsPageScreen(url: 'privacy-policy-cookie-restriction-mode'),
    setup: (locale) => accountSetup(
      locale,
      overrides: [
        cmsRepositoryProvider.overrideWithValue(
          FakeCmsRepository(
            pagesByUrl: {
              'privacy-policy-cookie-restriction-mode': _policy(locale == 'ar'),
            },
          ),
        ),
      ],
    ),
  ),
  // The same page with the HTML the first render test used (p1_screens_render
  // _test.dart): a list, a link and a table, which the policy above has none
  // of — the wide element on a narrow phone.
  AuditScene(
    frame: 'E28_cms_page',
    name: 'html_rich',
    screen: (_) =>
        const CmsPageScreen(url: 'privacy-policy-cookie-restriction-mode'),
    setup: (locale) => accountSetup(
      locale,
      overrides: [
        cmsRepositoryProvider.overrideWithValue(
          FakeCmsRepository(
            pagesByUrl: {
              'privacy-policy-cookie-restriction-mode': _privacyPage(
                locale == 'ar',
              ),
            },
          ),
        ),
      ],
    ),
  ),
];

/// A saved address of Figma 20 (the hub counts two of them).
const CustomerAddress _address = CustomerAddress(
  firstName: 'Sara',
  lastName: 'Ahmed',
  telephone: '+971501234567',
  street: 'Marina Walk',
  city: 'Dubai Marina',
);

/// The footer block of legal links, in the language of the capture.
Override _legalLinks(String locale) => cmsRepositoryProvider.overrideWithValue(
  FakeCmsRepository(
    blocks: {
      'hm_footer_legal': locale == 'ar'
          ? kLegalLinksBlock
                .replaceAll('>Privacy<', '>سياسة الخصوصية<')
                .replaceAll('>Terms<', '>الشروط والأحكام<')
                .replaceAll('>Cookies<', '>سياسة ملفات الارتباط<')
          : kLegalLinksBlock
                .replaceAll('>Privacy<', '>Privacy policy<')
                .replaceAll('>Terms<', '>Terms & conditions<')
                .replaceAll('>Cookies<', '>Cookie policy<'),
    },
  ),
);

/// The privacy policy of Figma 28, as the CMS would hold it (the Arabic
/// frame's wording for `ar`).
CmsPage _policy(bool ar) => CmsPage(
  identifier: 'privacy-policy-cookie-restriction-mode',
  title: ar ? 'سياسة الخصوصية' : 'Privacy policy',
  urlKey: 'privacy-policy-cookie-restriction-mode',
  content: ar
      ? '<p>توضح هذه السياسة ما يجمعه هب ماركت عند تسوقك معنا، ولماذا، والخيارات المتاحة لك.</p>'
            '<h2 id="a">ما نجمعه</h2><p>اسمك وبيانات التواصل وعناوين التوصيل؛ وطلباتك ومرتجعاتك وتقييماتك؛ ومعلومات الجهاز التي نستخدمها لحماية حسابك.</p>'
            '<h2 id="b">كيف نستخدمه</h2><p>لتوصيل طلباتك، ومشاركة بيانات التوصيل التي يحتاجها كل متجر، وتحصيل الدفع عبر شركائنا (البطاقة، تابي، تمارا)، وإرسال العروض — فقط بموافقتك.</p>'
            '<h2 id="c">خياراتك</h2><p>نزّل بياناتك أو احذف حسابك في أي وقت من حسابي ‹ الخصوصية والبيانات. ويمكنك إيقاف الرسائل التسويقية من الإشعارات.</p>'
            '<h2 id="d">ملفات الارتباط</h2><p>يحفظ التطبيق قدرًا بسيطًا من البيانات على جهازك لإبقائك مسجّلًا وتذكّر سلتك.</p>'
      : '<p>This policy explains what Hub Market collects when you shop with us, why, and the choices you have.</p>'
            '<h2 id="a">What we collect</h2><p>Your name, contact details and delivery addresses; your orders, returns and reviews; and device information we use to keep your account secure.</p>'
            '<h2 id="b">How we use it</h2><p>To deliver your orders, share the delivery details each store needs, take payment through our payment partners (card, Tabby, Tamara) and — only if you agree — send you offers.</p>'
            '<h2 id="c">Your choices</h2><p>Download your data or delete your account at any time from Account › Privacy &amp; data. You can switch marketing messages off in Notifications.</p>'
            '<h2 id="d">Cookies</h2><p>The app stores a small amount of data on your device to keep you signed in and remember your cart.</p>',
);

/// The same page with a list, a link and a table in it (the HTML of the first
/// render test, p1_screens_render_test.dart).
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

/// The three reviews of Figma 20f (the Arabic frame's wording for `ar`).
List<CustomerReview> _myReviews(bool ar) {
  CustomerReview review(
    String product,
    int stars,
    String date,
    String summary,
    String text,
  ) => CustomerReview(
    review: ProductReview(
      nickname: 'Sara',
      summary: summary,
      text: text,
      averageRating: stars * 20,
      date: date,
    ),
    productName: product,
    productUrlKey: 'p',
  );
  return ar
      ? [
          review(
            'فستان صدر طباعة الأزهار رباط مشد خصر',
            4,
            '2026-09-26 10:00:00',
            'قماش جميل ومقاس مضبوط',
            'الطبعة جميلة ورباط الخصر يعطي شكلًا رائعًا. وصل خلال يومين.',
          ),
          review(
            'كنبة سرير ركنه',
            5,
            '2026-08-14 10:00:00',
            'مريحة وسهلة التحويل',
            'وصلت وتم تركيبها في 20 دقيقة. اللون التركوازي مطابق للصورة.',
          ),
          review(
            'حليب جهينة كامل الدسم 1 لتر',
            4,
            '2026-08-02 10:00:00',
            'طازج وتاريخ صلاحية جيد',
            'وصل باردًا ومغلّفًا جيدًا.',
          ),
        ]
      : [
          review(
            'Floral Print Corset-Waist Tie Dress',
            4,
            '2026-09-26 10:00:00',
            'Lovely fabric, true to size',
            'Beautiful print and the tie waist is really flattering. Arrived in two days.',
          ),
          review(
            'Corner Sofa Bed',
            5,
            '2026-08-14 10:00:00',
            'Comfortable and easy to convert',
            'Delivered and assembled in 20 minutes. The teal colour is exactly as pictured.',
          ),
          review(
            'Juhayna Full Cream Milk 1 L',
            4,
            '2026-08-02 10:00:00',
            'Fresh with a good date',
            'Arrived cold and well packed.',
          ),
        ];
}

/// The left-to-right mark the frames put before an order number so it keeps
/// its place in Arabic (U+200E).
final String _lrm = String.fromCharCode(0x200E);

/// The five notifications of Figma 20g (the Arabic frame's wording for `ar`):
/// two unread from today, then yesterday and two older ones.
List<NotificationItem> _feed(bool ar) {
  final now = DateTime.now();
  NotificationItem item(
    String id,
    NotificationKind kind,
    DateTime at,
    String title,
    String body, {
    bool read = true,
    Map<String, dynamic> data = const {},
  }) => NotificationItem(
    id: id,
    kind: kind,
    title: title,
    body: body,
    receivedAt: at,
    read: read,
    data: data,
  );
  DateTime today(int h, int m) => DateTime(now.year, now.month, now.day, h, m);
  return [
    item(
      'n1',
      NotificationKind.order,
      today(8, 30),
      ar ? 'في الطريق إليك' : 'Out for delivery',
      ar
          ? 'الطرد 1 من الطلب $_lrm#HM-100248 من متجر لولي يصل اليوم قبل 9 مساءً.'
          : 'Package 1 of order $_lrm#HM-100248 from loly store arrives today by 9 pm.',
      read: false,
    ),
    item(
      'n2',
      NotificationKind.returns,
      today(9, 15),
      ar
          ? 'ردّ متجر لولي على طلب الإرجاع'
          : 'loly store replied to your return',
      ar
          ? 'سيستلم المندوب الإرجاع $_lrm#R-000031 الثلاثاء 30 سبتمبر، 10:00 – 14:00.'
          : 'A courier will collect return $_lrm#R-000031 on Tue 30 Sep, 10:00 – 14:00.',
      read: false,
    ),
    item(
      'n3',
      NotificationKind.wishlist,
      now.subtract(const Duration(days: 1)),
      ar ? 'انخفض سعر منتج في مفضلتك' : 'Price drop on your wishlist',
      ar
          ? 'فستان صدر طباعة الأزهار رباط مشد خصر أصبح بسعر 50 د.إ.'
          : 'Floral Print Corset-Waist Tie Dress is now AED 50.',
      // No `image` URL, as in the widget test.
    ),
    item(
      'n4',
      NotificationKind.credit,
      now.subtract(const Duration(days: 5)),
      ar ? 'أُضيف 43 د.إ إلى رصيدك' : 'AED 43 added to your credit',
      ar
          ? 'استرداد الإرجاع $_lrm#R-000031 جاهز للاستخدام.'
          : 'Refund for return $_lrm#R-000031 is ready to spend.',
    ),
    item(
      'n5',
      NotificationKind.promo,
      now.subtract(const Duration(days: 6)),
      ar ? 'عروض اليوم تنتهي عند منتصف الليل' : "Today's Deals end at midnight",
      ar
          ? 'خصم حتى 29% على البقالة والأثاث.'
          : 'Up to 29% off groceries and furniture.',
    ),
  ];
}
