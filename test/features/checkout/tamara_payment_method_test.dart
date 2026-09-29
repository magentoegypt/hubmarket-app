import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/payments/payment_order.dart';

/// Tamara went live on the store on 2026-09-28, served as
/// `tamara_pay_by_instalments`. The app renders whatever
/// `available_payment_methods` returns, so it appeared in checkout with no
/// release — which made both of these behaviours live at once.
const _tamara = PaymentMethodOption(
  code: 'tamara_pay_by_instalments',
  title: 'Tamara',
);

void main() {
  group('Tamara is a redirect method', () {
    test('never finalises on placeOrder as a cash-like method', () {
      // This is the one that mattered. isRedirect listed ngenius/tabby only,
      // so Tamara read as non-redirect and the app took the no-payment-step
      // path: Place Order went straight to order success with nothing paid.
      expect(_tamara.isRedirect, isTrue);
    });

    test('is recognised as Tamara but not as Tabby', () {
      expect(_tamara.isTamara, isTrue);
      expect(_tamara.isTabby, isFalse);
    });

    test('is not mistaken for cash on delivery', () {
      expect(isCodMethod(_tamara.code), isFalse);
    });
  });

  group('Tamara rewrites its own method code', () {
    // Backend note (2026-09-28): after payment Tamara rewrites the code to the
    // chosen instalment count, so the same method comes back as
    // `tamara_pay_by_instalments_4`. Everything keyed on the code must survive
    // that — these are substring matches, and this locks that in.
    const rewritten = PaymentMethodOption(
      code: 'tamara_pay_by_instalments_4',
      title: 'Tamara',
    );

    test('still reads as Tamara and as a redirect method', () {
      expect(rewritten.isTamara, isTrue);
      expect(rewritten.isRedirect, isTrue);
      expect(rewritten.isTabby, isFalse);
      expect(isCodMethod(rewritten.code), isFalse);
    });

    test('still ranks with instalments, not as an unknown method', () {
      // An unknown code sorts to the bottom, below Cash on Delivery — which is
      // where this would land if the match were exact rather than substring.
      expect(
        paymentRank(rewritten.code),
        paymentRank('tamara_pay_by_instalments'),
      );
      expect(
        paymentRank(rewritten.code),
        lessThan(paymentRank('cashondelivery')),
      );
    });
  });

  group('Tamara sits directly after Tabby', () {
    test('ranks between Tabby and Cash on Delivery', () {
      expect(
        paymentRank('tamara_pay_by_instalments'),
        greaterThan(paymentRank('tabby_installments')),
      );
      expect(
        paymentRank('tamara_pay_by_instalments'),
        lessThan(paymentRank('cashondelivery')),
      );
    });

    test('keeps both Tamara methods together, instalments first', () {
      // The store has tamara_pay_now and tamara_pay_by_instalments enabled;
      // only instalments is served so far. Ranked explicitly so the pair does
      // not reorder between requests when Pay Now does appear.
      final ordered = orderPayments(const [
        PaymentMethodOption(code: 'cashondelivery', title: 'COD'),
        PaymentMethodOption(code: 'tamara_pay_now', title: 'Tamara Pay Now'),
        PaymentMethodOption(code: 'tabby_installments', title: 'Tabby'),
        PaymentMethodOption(code: 'tamara_pay_by_instalments', title: 'Tamara'),
      ]);
      expect(ordered.map((m) => m.code).toList(), [
        'tabby_installments',
        'tamara_pay_by_instalments',
        'tamara_pay_now',
        'cashondelivery',
      ]);
    });

    test('treats Pay Now as a redirect method too', () {
      const payNow = PaymentMethodOption(
        code: 'tamara_pay_now',
        title: 'Tamara Pay Now',
      );
      expect(payNow.isRedirect, isTrue);
      expect(payNow.isTamara, isTrue);
    });

    test('orders the live method list the way the client asked', () {
      // Exactly what the store returns today, deliberately shuffled — the API
      // currently lists Tamara first.
      final ordered = orderPayments(const [
        PaymentMethodOption(code: 'tamara_pay_by_instalments', title: 'Tamara'),
        PaymentMethodOption(code: 'ngeniusonline_samsungpay', title: 'Samsung'),
        PaymentMethodOption(code: 'ngeniusonline', title: 'Visa & MC'),
        PaymentMethodOption(code: 'tabby_installments', title: 'Tabby'),
        PaymentMethodOption(code: 'cashondelivery', title: 'COD'),
      ]);
      expect(ordered.map((m) => m.code).toList(), [
        'ngeniusonline_samsungpay',
        'ngeniusonline',
        'tabby_installments',
        'tamara_pay_by_instalments',
        'cashondelivery',
      ]);
    });
  });
}
