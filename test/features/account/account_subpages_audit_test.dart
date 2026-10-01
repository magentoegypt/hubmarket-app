import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';
import 'package:hubmarket_app/features/account/presentation/screens/payment_methods_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/privacy_data_screen.dart';
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
