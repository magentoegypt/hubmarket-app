import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/account/presentation/screens/my_reviews_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/payment_methods_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/privacy_data_screen.dart';
import 'package:hubmarket_app/features/catalog/data/reviews_repository.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';
import 'package:hubmarket_app/features/catalog/domain/review_pages.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
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

void main() {
  setUpAll(loadAppFonts);

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
