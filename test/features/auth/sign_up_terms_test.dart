import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import 'auth_harness.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  Future<AuthHarness> pumpRegister(WidgetTester tester) async {
    useTallView(tester);
    final harness = AuthHarness(legalLinksBlock: kLegalLinksBlock);
    await tester.pumpWidget(harness.build(initialLocation: AppRoutes.signUp));
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets('Register links the terms and the privacy policy', (
    tester,
  ) async {
    final harness = await pumpRegister(tester);

    await tester.tapOnText(find.textRange.ofSubstring('Terms of Service'));
    await tester.pumpAndSettle();
    expect(find.text('PAGE customer-service'), findsOneWidget);

    // Opening a page didn't accept the terms on the customer's behalf.
    harness.router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, en.authCreateAccount));
    await tester.pumpAndSettle();
    expect(find.text(en.authAgreeTermsRequired), findsOneWidget);

    await tester.tapOnText(find.textRange.ofSubstring('Privacy Policy'));
    await tester.pumpAndSettle();
    expect(
      find.text('PAGE privacy-policy-cookie-restriction-mode'),
      findsOneWidget,
    );
  });

  testWidgets('the rest of the terms line still ticks the box', (tester) async {
    await pumpRegister(tester);

    await tester.tapOnText(find.textRange.ofSubstring('I agree to the'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, en.authCreateAccount));
    await tester.pumpAndSettle();
    expect(find.text(en.authAgreeTermsRequired), findsNothing);
    expect(find.textContaining('PAGE'), findsNothing);
  });
}
