import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';

List<String> _codes(List<PaymentMethodOption> methods) =>
    [for (final m in methods) m.code];

/// What `available_payment_methods` can hold: Magento's offline methods and
/// the online integrations (`is_deferred: true`) — the gateway methods of the
/// backend this app started from and Adobe Payment Services, installed on Hub
/// Market.
const _all = [
  PaymentMethodOption(code: 'cashondelivery', title: 'Cash On Delivery'),
  PaymentMethodOption(code: 'checkmo', title: 'Check / Money order'),
  PaymentMethodOption(code: 'banktransfer', title: 'Bank Transfer'),
  PaymentMethodOption(code: 'free', title: 'No Payment Information Required'),
  PaymentMethodOption(
    code: 'ngeniusonline',
    title: 'Visa & MasterCard',
    isOnline: true,
  ),
  PaymentMethodOption(
    code: 'tabby_installments',
    title: 'Tabby',
    isOnline: true,
  ),
  PaymentMethodOption(
    code: 'payment_services_paypal_hosted_fields',
    title: 'Credit Card',
    isOnline: true,
  ),
];

void main() {
  group('payableInApp', () {
    test('keeps only the offline methods, in the backend order', () {
      expect(
        _codes(payableInApp(_all)),
        ['cashondelivery', 'checkmo', 'banktransfer', 'free'],
      );
    });

    test('never adds a method', () {
      expect(payableInApp(const []), isEmpty);
    });
  });

  group('PaymentMethodOption', () {
    test('recognises cash on delivery across the common spellings', () {
      for (final code in [
        'cashondelivery',
        'phoenix_cashondelivery',
        'cash_on_delivery',
        'COD',
      ]) {
        expect(
          PaymentMethodOption(code: code, title: 'x').isCashOnDelivery,
          isTrue,
          reason: code,
        );
      }
      expect(
        const PaymentMethodOption(code: 'checkmo', title: 'x').isCashOnDelivery,
        isFalse,
      );
    });
  });
}
