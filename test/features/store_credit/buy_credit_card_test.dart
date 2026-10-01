import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/store_credit/domain/store_credit.dart';
import 'package:hubmarket_app/features/store_credit/presentation/buy_credit_card.dart';
import 'package:hubmarket_app/features/store_credit/presentation/my_credit_screen.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import '../../support/store_credit_fakes.dart';
import 'store_credit_harness.dart';

/// "AED 100" as the card writes it: a left-to-right isolate, so it keeps its
/// order inside Arabic text.
String _aed(String amount) => '\u2066AED $amount\u2069';

Future<FakeCartRepository> _pump(
  WidgetTester tester,
  FakeStoreCreditRepository credit, {
  FakeCartRepository? cart,
  String locale = 'en',
  double height = 1000,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = cart ?? FakeCartRepository();
  await tester.pumpWidget(
    storeCreditHarness(
      screen: const MyCreditScreen(),
      credit: credit,
      cart: repo,
      locale: locale,
      boundary: boundary,
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Finder _buyButton() => find.byType(FilledButton);

void main() {
  setUpAll(loadAppFonts);

  group('20d Buy credit', () {
    testWidgets('no card while the store sells no credit', (tester) async {
      final credit = FakeStoreCreditRepository();
      await _pump(tester, credit);

      expect(credit.topUpCalls, 1);
      expect(find.byType(BuyCreditCard), findsNothing);
      expect(find.text('Buy credit'), findsNothing);
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('offers the amounts on sale, the middle one chosen', (
      tester,
    ) async {
      await _pump(tester, FakeStoreCreditRepository(topUp: sampleTopUp()));

      expect(find.text('Buy credit'), findsOneWidget);
      expect(
        find.text('Top up now and pay for future orders in one tap.'),
        findsOneWidget,
      );
      for (final amount in ['50', '100', '250']) {
        expect(find.text(_aed(amount)), findsOneWidget);
      }
      // Figma 20d: AED 100 is chosen and the button says so.
      expect(find.text('Buy ${_aed('100')} credit'), findsOneWidget);
      // No custom amount without a product that takes one.
      expect(find.text('Other amount'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('buys the chosen amount and opens the cart', (tester) async {
      final cart = await _pump(
        tester,
        FakeStoreCreditRepository(topUp: sampleTopUp()),
      );

      await tester.tap(find.text(_aed('250')));
      await tester.pumpAndSettle();
      expect(find.text('Buy ${_aed('250')} credit'), findsOneWidget);

      await tester.tap(_buyButton());
      await tester.pumpAndSettle();

      expect(cart.creditAmounts, [250.0]);
      expect(find.text('route /cart'), findsOneWidget);
    });

    testWidgets('Other amount takes a whole amount within the range', (
      tester,
    ) async {
      final cart = await _pump(
        tester,
        FakeStoreCreditRepository(topUp: sampleTopUp(custom: true)),
      );

      await tester.tap(find.text('Other amount'));
      await tester.pumpAndSettle();
      expect(find.text('Amount of credit'), findsOneWidget);
      expect(
        find.text('From ${_aed('10')} to ${_aed('1,000')}'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), '5');
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Enter a whole amount from ${_aed('10')} to ${_aed('1,000')}.',
        ),
        findsOneWidget,
      );
      // Nothing to buy yet: the button reads "Buy credit" and is off.
      expect(tester.widget<FilledButton>(_buyButton()).onPressed, isNull);
      expect(
        find.descendant(of: _buyButton(), matching: find.text('Buy credit')),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), '150');
      await tester.pumpAndSettle();
      expect(find.text('Buy ${_aed('150')} credit'), findsOneWidget);

      await tester.tap(_buyButton());
      await tester.pumpAndSettle();
      expect(cart.creditAmounts, [150.0]);
      expect(find.text('route /cart'), findsOneWidget);
    });

    testWidgets('only a custom amount: the field alone, from the smallest', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeStoreCreditRepository(
          topUp: StoreCreditTopUp(
            sku: 'hm-credit-any',
            min: aedCredit(10),
            max: aedCredit(1000),
            creditRate: 1,
          ),
        ),
      );

      expect(find.text('Other amount'), findsNothing);
      expect(find.text(_aed('50')), findsNothing);
      // The website's slider starts at the smallest amount.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '10',
      );
      expect(find.text('Buy ${_aed('10')} credit'), findsOneWidget);
    });

    testWidgets('says the price when it differs from the credit', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeStoreCreditRepository(topUp: sampleTopUp(price100: 90)),
      );

      expect(find.text('You pay \u2066AED 90\u2069'), findsOneWidget);
      await tester.tap(find.text(_aed('50')));
      await tester.pumpAndSettle();
      expect(find.textContaining('You pay'), findsNothing);
    });

    testWidgets('a refusal is said and the page stays', (tester) async {
      final cart = FakeCartRepository()
        ..addCreditFailure = const Failure(
          FailureKind.server,
          detail: 'Store credit can\'t be bought at the moment.',
        );
      await _pump(
        tester,
        FakeStoreCreditRepository(topUp: sampleTopUp()),
        cart: cart,
      );

      await tester.tap(_buyButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Store credit can\'t be bought at the moment.'),
        findsOneWidget,
      );
      expect(find.byType(MyCreditScreen), findsOneWidget);
      expect(find.text('route /cart'), findsNothing);
    });

    testWidgets('a failed network says so', (tester) async {
      final cart = FakeCartRepository()
        ..addCreditFailure = const Failure(FailureKind.network);
      await _pump(
        tester,
        FakeStoreCreditRepository(topUp: sampleTopUp()),
        cart: cart,
      );

      await tester.tap(_buyButton());
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('route /cart'), findsNothing);
    });

    testWidgets('a failed top-up lookup hides only the card', (tester) async {
      final credit = FakeStoreCreditRepository(topUp: sampleTopUp())
        ..topUpError = const Failure(FailureKind.server, detail: 'boom');
      await _pump(tester, credit);

      expect(find.byType(BuyCreditCard), findsNothing);
      expect(find.text('AED 120.00'), findsOneWidget);
      expect(find.text('Refund to credit'), findsOneWidget);
    });
  });

  group('20d Buy credit renders', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('20d Buy credit, other amount ($locale)', (tester) async {
        final key = GlobalKey();
        await withRealShadows(() async {
          await _pump(
            tester,
            FakeStoreCreditRepository(
              topUp: sampleTopUp(custom: true),
              pages: [sampleCreditAccount(arabic: locale == 'ar')],
            ),
            locale: locale,
            height: 900,
            boundary: key,
          );
          await tester.tap(
            find.text(locale == 'ar' ? 'مبلغ آخر' : 'Other amount'),
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), '150');
          await tester.pumpAndSettle();
          await captureScreen(tester, key, '20d_buy_credit_other_$locale');
        });
        expect(
          Directionality.of(tester.element(find.byType(BuyCreditCard))),
          locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
