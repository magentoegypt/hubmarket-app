import 'package:flutter/material.dart' show Locale, TextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/core/widgets/hub_switch.dart';
import 'package:hubmarket_app/features/account/domain/profile_extras.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/account/presentation/profile_extras_provider.dart';
import 'package:hubmarket_app/features/account/presentation/screens/edit_profile_screen.dart';
import 'package:hubmarket_app/features/auth/presentation/widgets/auth_field.dart';
import 'package:hubmarket_app/features/account/presentation/screens/help_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/my_reviews_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/payment_methods_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/privacy_data_screen.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/cms_page.dart';
import 'package:hubmarket_app/features/cms/presentation/cms_page_screen.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_screen.dart';
import 'package:hubmarket_app/features/notifications/presentation/notifications_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import 'audit_harness.dart';

/// Renders the Account sub-pages as their Figma frames draw them (and the
/// Arabic twins) to `build/test_screens/<capture>_<locale>.png`, the names
/// `tool/ui_audit/pairs.py` pairs with the frames. Each render also fails on
/// a layout exception, so it doubles as an RTL and overflow smoke test.

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
          ? 'الطرد 1 من الطلب ‎#HM-100248 من متجر لولي يصل اليوم قبل 9 مساءً.'
          : 'Package 1 of order ‎#HM-100248 from loly store arrives today by 9 pm.',
      read: false,
    ),
    item(
      'n2',
      NotificationKind.returns,
      today(9, 15),
      ar ? 'ردّ متجر لولي على طلب الإرجاع' : 'loly store replied to your return',
      ar
          ? 'سيستلم المندوب الإرجاع ‎#R-000031 الثلاثاء 30 سبتمبر، 10:00 – 14:00.'
          : 'A courier will collect return ‎#R-000031 on Tue 30 Sep, 10:00 – 14:00.',
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
      // No `image` URL: a network image never settles in a widget test.
    ),
    item(
      'n4',
      NotificationKind.credit,
      now.subtract(const Duration(days: 5)),
      ar ? 'أُضيف 43 د.إ إلى رصيدك' : 'AED 43 added to your credit',
      ar
          ? 'استرداد الإرجاع ‎#R-000031 جاهز للاستخدام.'
          : 'Refund for return ‎#R-000031 is ready to spend.',
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

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => NotificationInbox.instance.items.value = const []);

  for (final locale in const ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('20b Privacy & data ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const PrivacyDataScreen(),
        locale: locale,
        overrides: [_legalLinks(locale)],
      );
      // The frame draws the box ticked.
      await tester.tap(find.text(l10n.deleteAccountUnderstand));
      await tester.pumpAndSettle();
      await captureAudit(tester, boundary, '20b_privacy_data', locale);
    });

    testWidgets('20f My product reviews ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const MyReviewsScreen(),
        locale: locale,
        overrides: [
          reviewsRepositoryProvider.overrideWithValue(
            FakeReviewsRepository(customerReviews: _myReviews(locale == 'ar')),
          ),
        ],
      );
      await captureAudit(tester, boundary, '20f_my_reviews', locale);
    });

    testWidgets('28 Content page ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const CmsPageScreen(
          url: 'privacy-policy-cookie-restriction-mode',
        ),
        locale: locale,
        overrides: [
          cmsRepositoryProvider.overrideWithValue(
            FakeCmsRepository(
              pagesByUrl: {
                'privacy-policy-cookie-restriction-mode': _policy(locale == 'ar'),
              },
            ),
          ),
        ],
      );
      await captureAudit(tester, boundary, '28_content_page', locale);
    });

    testWidgets('27 Help centre ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const HelpScreen(),
        locale: locale,
        // The frame's full scroll (1460 / 1486) plus the tab bar the app keeps.
        height: (locale == 'ar' ? 1486 : 1460) + 100,
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
        ],
      );
      // The frame draws the message filled in.
      await tester.enterText(
        find.byType(TextField).last,
        locale == 'ar'
            ? 'الطرد الثاني من متجر ميا لم يتحرك منذ الاثنين — الطلب HM-100248.'
            : 'My second package from MIA CO hasn’t moved since Monday — order HM-100248.',
      );
      await tester.pumpAndSettle();
      await captureAudit(tester, boundary, '27_help_centre', locale);
    });

    testWidgets('20c Profile details ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const EditProfileScreen(),
        locale: locale,
        // The frame's full scroll (1124 / 1146) plus the tab bar the app keeps.
        height: (locale == 'ar' ? 1146 : 1124) + 100,
        overrides: [
          profileExtrasProvider.overrideWith(
            (ref) async => const ProfileExtras(
              dateOfBirth: '1994-03-12',
              emailConfirmed: true,
            ),
          ),
        ],
      );
      // The frame draws Change password open, with a ten-character password
      // that has a letter, a digit and no symbol: three bars.
      await tester.tap(find.byType(HubSwitch));
      await tester.pumpAndSettle();
      Finder field(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(AuthField)),
        matching: find.byType(TextField),
      );
      await tester.enterText(field(l10n.fieldCurrentPassword), 'password1');
      await tester.enterText(field(l10n.fieldNewPassword), 'Password12');
      await tester.enterText(field(l10n.profileConfirmNewPassword), 'Password12');
      await tester.pumpAndSettle();
      await captureAudit(tester, boundary, 'audit_20c_profile', locale);
    });

    testWidgets('20g Notifications ($locale)', (tester) async {
      NotificationInbox.instance.items.value = _feed(locale == 'ar');
      final boundary = await pumpAuditScreen(
        tester,
        screen: const NotificationsScreen(),
        locale: locale,
      );
      await captureAudit(tester, boundary, 'audit_20g_notifications', locale);
    });

    testWidgets('20h Notification settings ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const NotificationSettingsScreen(),
        locale: locale,
        overrides: [
          // Subscribed, as the frame's ticked box says.
          accountRepositoryProvider.overrideWithValue(
            FakeAccountRepository(newsletterSubscribed: true),
          ),
        ],
      );
      // The frame draws Deals & offers off and Save ready: switch it off.
      await tester.tap(find.byType(HubSwitch));
      await tester.pumpAndSettle();
      await captureAudit(tester, boundary, '20h_notification_settings', locale);
    });

    testWidgets('20e Stored payment methods ($locale)', (tester) async {
      final boundary = await pumpAuditScreen(
        tester,
        screen: const PaymentMethodsScreen(),
        locale: locale,
        overrides: [
          savedCardsProvider.overrideWith(
            (ref) async => const [
              SavedCard(
                publicHash: 'h1',
                brandCode: 'VI',
                last4: '4242',
                expiryMonth: 8,
                expiryYear: 2028,
              ),
              SavedCard(
                publicHash: 'h2',
                brandCode: 'MC',
                last4: '5100',
                expiryMonth: 11,
                expiryYear: 2027,
              ),
            ],
          ),
        ],
      );
      await captureAudit(tester, boundary, 'audit_20e_payment_methods', locale);
    });
  }
}
