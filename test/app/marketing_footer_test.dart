import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/shell/marketing_footer.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/config/store_contact.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/widgets/brand_logo.dart';
import 'package:hubmarket_app/core/widgets/brand_wordmark.dart';
import 'package:hubmarket_app/features/newsletter/data/newsletter_repository.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../support/fakes.dart';

const _testContact = StoreContact(
  company: 'Hub Market Perfume & Cosmetics Trading LLC',
  address: 'HHHR Tower, Dubai, UAE',
  phone: '+971500000000',
  phoneDisplay: '+971 50 000 0000',
  email: 'info@hub-market.magento2.click',
  hours: '',
  whatsapp: 'https://wa.me/971500000000',
  website: 'https://hub-market.magento2.click',
  facebook: 'https://facebook.com/hubmarket',
  instagram: 'https://instagram.com/hubmarket',
);

/// Stands in for the live mutation so the footer's success / double-opt-in /
/// failure branches can each be driven. Extends the real repository so a
/// signature change breaks this fake at compile time.
class _FakeNewsletterRepository extends NewsletterRepository {
  _FakeNewsletterRepository(this._outcome) : super(fakeGraphQLClient());

  /// A [NewsletterSubscription] to return, or a [Failure] to throw.
  final Object _outcome;
  String? lastEmail;

  @override
  Future<NewsletterSubscription> subscribe(String email) async {
    lastEmail = email;
    final outcome = _outcome;
    if (outcome is Failure) throw outcome;
    return outcome as NewsletterSubscription;
  }
}

Future<void> _pump(WidgetTester tester, {NewsletterRepository? newsletter}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storeContactProvider.overrideWithValue(_testContact),
        if (newsletter != null)
          newsletterRepositoryProvider.overrideWithValue(newsletter),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: MarketingFooter()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('newsletter rejects an invalid email', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pump(); // surface the snackbar
    expect(find.text('Enter a valid email'), findsOneWidget);
  });

  testWidgets('newsletter confirms only after the backend subscribes', (
    tester,
  ) async {
    final repo = _FakeNewsletterRepository(NewsletterSubscription.subscribed);
    await _pump(tester, newsletter: repo);
    await tester.enterText(find.byType(TextField), ' shopper@example.com ');
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pumpAndSettle();

    // Trimmed before it reaches Magento — a stray space would be rejected.
    expect(repo.lastEmail, 'shopper@example.com');
    expect(find.text("Thanks! We'll keep you posted."), findsOneWidget);
  });

  testWidgets('double opt-in asks the user to confirm, not "subscribed"', (
    tester,
  ) async {
    await _pump(
      tester,
      newsletter: _FakeNewsletterRepository(
        NewsletterSubscription.pendingConfirmation,
      ),
    );
    await tester.enterText(find.byType(TextField), 'shopper@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pumpAndSettle();

    expect(
      find.text('Almost there — check your inbox to confirm your subscription.'),
      findsOneWidget,
    );
    expect(find.text("Thanks! We'll keep you posted."), findsNothing);
  });

  testWidgets('a failed sign-up reports the error and keeps the email', (
    tester,
  ) async {
    // The regression this guards: the footer used to confirm unconditionally.
    await _pump(
      tester,
      newsletter: _FakeNewsletterRepository(
        const Failure(FailureKind.network),
      ),
    );
    await tester.enterText(find.byType(TextField), 'shopper@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Subscribe'));
    await tester.pumpAndSettle();

    expect(find.text("Thanks! We'll keep you posted."), findsNothing);
    // Text survives so the user can retry without retyping.
    expect(find.text('shopper@example.com'), findsOneWidget);
  });

  testWidgets('footer links are tappable widgets', (tester) async {
    await _pump(tester);
    // About Us + Customer Service columns render with tappable link rows,
    // matching the website footer grouping.
    expect(find.text('About Us'), findsWidgets);
    expect(find.text('Track Order'), findsOneWidget);
    expect(find.text('Shipping & Delivery'), findsOneWidget);
    expect(find.text('Returns & Exchanges'), findsOneWidget);
    expect(find.byType(InkWell), findsWidgets);
  });

  testWidgets('the brand mark is the text wordmark, not the lockup image', (
    tester,
  ) async {
    await _pump(tester);
    // The storefront's `.beauty-footer__brand` is text; QA rejected the Z-mark
    // lockup here (CL042-QA01), so pin the direction against a future revert.
    expect(find.byType(BrandWordmark), findsOneWidget);
    expect(find.text('Hub Market'), findsOneWidget);
    expect(find.byType(BrandLogo), findsNothing);

    // Both pinned on the widget itself: the base theme font is Cairo in Arabic
    // and the footer is RTL there, but the Latin brand name inherits neither.
    final mark = tester.widget<Text>(
      find.descendant(
        of: find.byType(BrandWordmark),
        matching: find.byType(Text),
      ),
    );
    expect(mark.style?.fontFamily, AppTheme.latinFont);
    expect(mark.textDirection, TextDirection.ltr);
  });
}
