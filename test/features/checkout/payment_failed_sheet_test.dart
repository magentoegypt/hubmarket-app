import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/domain/payment_refusal.dart';
import 'package:hubmarket_app/features/checkout/presentation/widgets/payment_failed_sheet.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/fonts.dart';
import 'checkout_harness.dart';

/// S5 "Payment failed": the sheet itself, the way checkout opens it when the
/// store refuses the payment, and the refusals that stay a one-line message.

/// The store refusing a card — what a gateway answers on `placeOrder`.
const _declined = Failure(
  FailureKind.server,
  detail: 'Your card was declined: insufficient funds (code 51).',
);

/// `placeOrder` refused with [error]; everything before it works.
class _RefusingCheckout extends FakeCheckoutRepository {
  _RefusingCheckout(this.error, {required super.paymentMethods})
    : super(
        shippingMethods: kShippingMethods,
        grandTotal: aed(553),
        orderResult: const PlaceOrderResult(orderNumber: '000000248'),
      );

  final Object error;

  @override
  Future<PlaceOrderResult> placeOrder(String cartId) async {
    calls.add('placeOrder');
    throw error;
  }
}

const _cod = PaymentMethodOption(
  code: 'cashondelivery',
  title: 'Cash on delivery',
);
const _checkmo = PaymentMethodOption(
  code: 'checkmo',
  title: 'Check / Money order',
);

void main() {
  setUpAll(loadAppFonts);

  group('paymentRefusalReason', () {
    test('a store message about the payment is the reason', () {
      expect(paymentRefusalReason(_declined), _declined.detail);
      expect(
        paymentRefusalReason(
          const Failure(
            FailureKind.server,
            detail: 'The requested Payment Method is not available.',
          ),
        ),
        'The requested Payment Method is not available.',
      );
      // The Arabic store view words it in Arabic.
      expect(
        paymentRefusalReason(
          const Failure(FailureKind.server, detail: 'تم رفض البطاقة.'),
        ),
        'تم رفض البطاقة.',
      );
    });

    test('stock, connection and unclassified failures are not payment', () {
      expect(
        paymentRefusalReason(
          const Failure(
            FailureKind.server,
            detail: 'Some of the products are out of stock.',
          ),
        ),
        isNull,
      );
      expect(paymentRefusalReason(const Failure(FailureKind.network)), isNull);
      expect(
        paymentRefusalReason(
          const Failure(FailureKind.unknown, detail: 'card declined'),
        ),
        isNull,
      );
      expect(paymentRefusalReason(StateError('x')), isNull);
      expect(paymentRefusalReason(null), isNull);
      expect(
        paymentRefusalReason(const Failure(FailureKind.server, detail: ' ')),
        isNull,
      );
    });
  });

  Widget sheetApp(
    String locale,
    GlobalKey key,
    void Function(BuildContext) go,
  ) => RepaintBoundary(
    key: key,
    child: MaterialApp(
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
      // Figma S5: the page under the scrim is a blank white one.
      home: Builder(
        builder: (context) => Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: TextButton(
              onPressed: () => go(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> open(
    WidgetTester tester,
    String locale, {
    GlobalKey? key,
    String? reason = 'insufficient funds (code 51)',
    bool tryAnother = true,
    bool cod = true,
  }) async {
    await tester.pumpWidget(
      sheetApp(locale, key ?? GlobalKey(), (context) {
        showPaymentFailedSheet(
          context,
          methodTitle: 'Visa •••• 4242',
          reason: reason,
          canTryAnotherMethod: tryAnother,
          canPayCashOnDelivery: cod,
        );
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  for (final locale in ['en', 'ar']) {
    final l10n = lookupAppLocalizations(Locale(locale));

    testWidgets('audit_S5_payment_failed ($locale)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await open(tester, locale, key: key);
      await captureScreen(tester, key, 'audit_S5_payment_failed_$locale');

      expect(find.text(l10n.paymentFailedTitle), findsOneWidget);
      expect(
        find.text(l10n.paymentFailedBody('Visa •••• 4242')),
        findsOneWidget,
      );
      expect(
        find.text(l10n.paymentFailedReason('insufficient funds (code 51)')),
        findsOneWidget,
      );
      expect(find.text(l10n.paymentFailedTryAnother), findsOneWidget);
      expect(find.text(l10n.paymentFailedPayCod), findsOneWidget);
      expect(find.text(l10n.paymentFailedBackToCart), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(PaymentFailedSheet))),
        locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('each button resolves with its own action', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final actions = <String, PaymentFailedAction>{
      l10n.paymentFailedTryAnother: PaymentFailedAction.tryAnotherMethod,
      l10n.paymentFailedPayCod: PaymentFailedAction.payCashOnDelivery,
      l10n.paymentFailedBackToCart: PaymentFailedAction.backToCart,
    };
    for (final entry in actions.entries) {
      PaymentFailedAction? chosen;
      await tester.pumpWidget(
        sheetApp('en', GlobalKey(), (context) {
          showPaymentFailedSheet(
            context,
            methodTitle: 'Visa •••• 4242',
            canTryAnotherMethod: true,
            canPayCashOnDelivery: true,
          ).then((a) => chosen = a);
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(chosen, entry.value, reason: entry.key);
      expect(find.byType(PaymentFailedSheet), findsNothing);
    }
  });

  testWidgets('a way on the order cannot take is left out', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));
    await open(tester, 'en', reason: null, tryAnother: false, cod: false);

    expect(find.text(l10n.paymentFailedTryAnother), findsNothing);
    expect(find.text(l10n.paymentFailedPayCod), findsNothing);
    // Back to the cart is always there; no reason row without a reason.
    expect(find.text(l10n.paymentFailedBackToCart), findsOneWidget);
    expect(find.textContaining('Reason'), findsNothing);
  });

  group('checkout', () {
    Future<void> toReview(
      WidgetTester tester,
      FakeCheckoutRepository repo, {
      String? pick,
    }) async {
      tester.view.physicalSize = const Size(390, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        checkoutHarness(locale: 'en', repository: repo, signedIn: true),
      );
      await tester.pumpAndSettle();
      await tapText(tester, 'Continue to payment');
      if (pick != null) await tapText(tester, pick);
      await tapText(tester, 'Review order');
    }

    testWidgets('a refused payment opens the declined sheet, not a snackbar', (
      tester,
    ) async {
      final repo = _RefusingCheckout(_declined, paymentMethods: const [_cod]);
      await toReview(tester, repo);
      await tapText(tester, 'Place order · AED 553');

      expect(repo.calls, contains('placeOrder'));
      expect(find.text('Payment declined'), findsOneWidget);
      expect(
        find.text(
          "Cash on delivery was declined. You haven't been charged — your "
          'cart and delivery choices are saved.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reason: ${_declined.detail}'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      // Cash on delivery is the method that failed and the only one: nothing
      // to switch to, only the way back.
      expect(find.text('Try another method'), findsNothing);
      expect(find.text('Pay cash on delivery'), findsNothing);

      await tapText(tester, 'Back to cart');
      expect(find.text('route /cart'), findsOneWidget);
    });

    testWidgets('"Try another method" returns to the payment step', (
      tester,
    ) async {
      final repo = _RefusingCheckout(
        _declined,
        paymentMethods: const [_cod, _checkmo],
      );
      await toReview(tester, repo);
      await tapText(tester, 'Place order · AED 553');

      expect(find.text('Try another method'), findsOneWidget);
      await tapText(tester, 'Try another method');
      expect(find.text('Payment method'), findsOneWidget);
      expect(find.text('Review your order'), findsNothing);
    });

    testWidgets('"Pay cash on delivery" switches the order to cash', (
      tester,
    ) async {
      final repo = _RefusingCheckout(
        _declined,
        paymentMethods: const [_cod, _checkmo],
      );
      // The shopper chose the check; it is refused.
      await toReview(tester, repo, pick: 'Check / Money order');
      expect(find.text('Check / Money order'), findsWidgets);
      await tapText(tester, 'Place order · AED 553');

      expect(find.text('Pay cash on delivery'), findsOneWidget);
      await tapText(tester, 'Pay cash on delivery');
      expect(repo.selectedPaymentCode, 'cashondelivery');
      // Back on the review, which now names cash on delivery.
      expect(find.text('Review your order'), findsOneWidget);
      expect(find.text('Cash on delivery'), findsOneWidget);
    });

    testWidgets('a refusal that is not about payment stays a snackbar', (
      tester,
    ) async {
      final repo = _RefusingCheckout(
        const Failure(
          FailureKind.server,
          detail: 'Some of the products are out of stock.',
        ),
        paymentMethods: const [_cod],
      );
      await toReview(tester, repo);
      await tapText(tester, 'Place order · AED 553');

      expect(find.text('Payment declined'), findsNothing);
      expect(
        find.text('Some of the products are out of stock.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });
  });
}
