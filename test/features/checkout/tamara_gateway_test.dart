import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/payment_session.dart';
import 'package:hubmarket_app/features/checkout/payments/tamara_payment_gateway.dart';

PaymentOutcome? _classify(String url) => classifyTamaraReturn(Uri.parse(url));

void main() {
  // Backend contract (2026-09-28):
  //   {base}tamara/payment/{ORDER_ENTITY_ID}/{success|cancel|failure}
  // matched on the PATH SEGMENT — Magento reads no query parameters, so
  // anything Tamara appends is noise.
  group('classifyTamaraReturn', () {
    test('reads the verdict from the last path segment', () {
      expect(
        _classify('https://hub-market.magento2.click/tamara/payment/4821/success'),
        PaymentOutcome.success,
      );
      expect(
        _classify('https://hub-market.magento2.click/tamara/payment/4821/cancel'),
        PaymentOutcome.cancelled,
      );
      expect(
        _classify('https://hub-market.magento2.click/tamara/payment/4821/failure'),
        PaymentOutcome.failed,
      );
    });

    test('ignores whatever Tamara appends as query', () {
      expect(
        _classify(
          'https://hub-market.magento2.click/tamara/payment/4821/success'
          '?paymentStatus=declined&orderId=abc',
        ),
        PaymentOutcome.success,
      );
    });

    test('works under a store-view path prefix', () {
      expect(
        _classify('https://hub-market.magento2.click/eg_en/tamara/payment/4821/success'),
        PaymentOutcome.success,
      );
    });

    test('is not fooled by a store page that merely ends in success', () {
      // The route is part of the match, not just the verdict.
      expect(_classify('https://hub-market.magento2.click/checkout/success'), isNull);
      expect(_classify('https://hub-market.magento2.click/'), isNull);
    });

    test('does not treat the server-to-server endpoint as a verdict', () {
      expect(
        _classify('https://hub-market.magento2.click/tamara/payment/notification?storeId=1'),
        isNull,
      );
    });
  });

  group('TamaraPaymentGateway', () {
    testWidgets('refuses a session with no web_url rather than opening an empty sheet', (
      tester,
    ) async {
      const gateway = TamaraPaymentGateway(host: 'hub-market.magento2.click');
      const session = PaymentSession(
        orderNumber: '000000600',
        methodCode: 'tamara_pay_by_instalments',
        gateway: PaymentProvider.tamara,
        status: PaymentSessionStatus.ready,
      );

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(await gateway.present(ctx, session), PaymentOutcome.failed);
    });

    testWidgets('refuses when the store host is unknown', (tester) async {
      // Without it there is no way to tell a return from a payment step, so
      // presenting would risk reading a 3-D Secure page as an outcome.
      const gateway = TamaraPaymentGateway(host: '');
      const session = PaymentSession(
        orderNumber: '000000601',
        methodCode: 'tamara_pay_by_instalments',
        gateway: PaymentProvider.tamara,
        status: PaymentSessionStatus.ready,
        webUrl: 'https://checkout.tamara.co/checkout/abc',
      );

      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(await gateway.present(ctx, session), PaymentOutcome.failed);
    });
  });
}
