import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/checkout_review_step.dart';
import 'package:hubmarket_app/features/cms/data/cms_repository.dart';
import 'package:hubmarket_app/features/cms/domain/cms_links.dart';
import 'package:hubmarket_app/features/cms/presentation/widgets/legal_links_text.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

/// The live `hm_footer_legal` block of store `ar` (30 Sep 2026).
const String _arabicLegalBlock =
    '<ul><li><a href="https://hub-market.magento2.click/ar/privacy-policy-cookie-restriction-mode/">الخصوصية</a></li>'
    '<li><a href="https://hub-market.magento2.click/ar/customer-service/">الشروط</a></li>'
    '<li><a href="https://hub-market.magento2.click/ar/enable-cookies/">ملفات الارتباط</a></li></ul>';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String? block = kLegalLinksBlock,
  String locale = 'en',
}) async {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(
        path: '/screen',
        builder: (_, __) => Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
      GoRoute(
        path: AppRoutes.cmsPage,
        builder: (_, state) => Scaffold(
          body: Text(
            'PAGE ${state.uri.queryParameters['url']} '
            '(${state.uri.queryParameters['title']})',
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        storeRepositoryProvider.overrideWithValue(
          FakeStoreRepository(kSampleStores),
        ),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        cmsRepositoryProvider.overrideWithValue(
          FakeCmsRepository(
            blocks: {if (block != null) 'hm_footer_legal': block},
          ),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The spans of the (only) rich text under [finder] that carry a link.
List<String> _linkedWords(WidgetTester tester, Finder finder) {
  final words = <String>[];
  tester.widget<RichText>(finder).text.visitChildren((span) {
    if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
      words.add(span.text ?? '');
    }
    return true;
  });
  return words;
}

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  group('legal links of hm_footer_legal', () {
    test('classifies the live English block', () {
      final links = linksFromHtml(kLegalLinksBlock);
      expect(links.map(legalPageOf), [
        LegalPage.privacy,
        LegalPage.terms,
        LegalPage.cookies,
      ]);
      // No terms page yet: "Terms" opens customer-service, as on the website.
      expect(
        legalLinkFor(links, LegalPage.terms)?.url,
        'https://hub-market.magento2.click/en/customer-service/',
      );
      expect(
        legalLinkFor(links, LegalPage.privacy)?.url,
        endsWith('/privacy-policy-cookie-restriction-mode/'),
      );
      expect(
        legalLinkFor(links, LegalPage.cookies)?.url,
        endsWith('/enable-cookies/'),
      );
    });

    test('classifies the live Arabic block by its labels', () {
      final links = linksFromHtml(_arabicLegalBlock);
      expect(legalLinkFor(links, LegalPage.terms)?.label, 'الشروط');
      expect(legalLinkFor(links, LegalPage.privacy)?.label, 'الخصوصية');
      expect(legalLinkFor(links, LegalPage.cookies)?.label, 'ملفات الارتباط');
    });

    test('terms prefers a link that names terms, and may be missing', () {
      const other = CmsLink(label: 'Sitemap', url: 'https://x.test/sitemap');
      const terms = CmsLink(
        label: 'Terms & Conditions',
        url: 'https://x.test/en/terms-conditions/',
      );
      expect(legalLinkFor(const [other, terms], LegalPage.terms), terms);
      expect(legalLinkFor(const [], LegalPage.terms), isNull);
      expect(
        legalLinkFor(
          linksFromHtml(kLegalLinksBlock).sublist(0, 1),
          LegalPage.terms,
        ),
        isNull,
        reason: 'only Privacy in the block',
      );
    });

    test('splits tagged wording into plain and linked runs', () {
      expect(legalTextParts(en.authAgreeTerms), [
        (text: 'I agree to the ', page: null),
        (text: 'Terms of Service', page: LegalPage.terms),
        (text: ' and ', page: null),
        (text: 'Privacy Policy', page: LegalPage.privacy),
      ]);
      expect(legalTextParts('Plain words'), [
        (text: 'Plain words', page: null),
      ]);
      expect(legalTextParts('An <terms>unclosed tag'), [
        (text: 'An <terms>unclosed tag', page: null),
      ]);
      expect(legalTextParts(''), isEmpty);
    });
  });

  group('LegalLinksText', () {
    testWidgets('links the tagged words to the store pages', (tester) async {
      await _pump(tester, LegalLinksText(en.authAgreeTerms));

      final text = find.text(
        'I agree to the Terms of Service and Privacy Policy',
        findRichText: true,
      );
      expect(text, findsOneWidget);
      expect(_linkedWords(tester, text), [
        'Terms of Service',
        'Privacy Policy',
      ]);

      await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE customer-service (Terms)'), findsOneWidget);
    });

    testWidgets('Privacy Policy opens the privacy page', (tester) async {
      await _pump(tester, LegalLinksText(en.authAgreeTerms));
      await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
      await tester.pumpAndSettle();
      expect(
        find.text('PAGE privacy-policy-cookie-restriction-mode (Privacy)'),
        findsOneWidget,
      );
    });

    testWidgets('without the block the sentence stays plain', (tester) async {
      await _pump(tester, LegalLinksText(en.authAgreeTerms), block: null);
      final text = find.text(
        'I agree to the Terms of Service and Privacy Policy',
        findRichText: true,
      );
      expect(text, findsOneWidget);
      expect(_linkedWords(tester, text), isEmpty);
    });

    testWidgets('Arabic wording links the Arabic pages', (tester) async {
      await _pump(
        tester,
        LegalLinksText(ar.authAgreeTerms),
        block: _arabicLegalBlock,
        locale: 'ar',
      );
      final text = find.text(
        'أوافق على شروط الخدمة وسياسة الخصوصية',
        findRichText: true,
      );
      expect(text, findsOneWidget);
      expect(_linkedWords(tester, text), ['شروط الخدمة', 'سياسة الخصوصية']);
    });
  });

  testWidgets('checkout review: "Terms" opens the terms page', (tester) async {
    await _pump(tester, const ReviewTermsNote());
    final text = find.text(
      'By placing your order you agree to Hub Market’s Terms and each '
      'store’s return policy.',
      findRichText: true,
    );
    expect(text, findsOneWidget);
    expect(_linkedWords(tester, text), ['Terms']);

    await tester.tapOnText(find.textRange.ofSubstring('Terms'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE customer-service (Terms)'), findsOneWidget);
  });
}
