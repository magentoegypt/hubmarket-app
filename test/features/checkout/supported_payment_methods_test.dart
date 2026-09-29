import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/config/backend_capabilities.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/domain/tabby_config.dart';
import 'package:hubmarket_app/features/checkout/payments/payment_order.dart';
import 'package:hubmarket_app/features/checkout/payments/tabby_promo.dart';

import '../../support/fakes.dart';

List<String> _codes(List<PaymentMethodOption> methods) =>
    [for (final m in methods) m.code];

const _all = [
  PaymentMethodOption(code: 'cashondelivery', title: 'Cash On Delivery'),
  PaymentMethodOption(code: 'checkmo', title: 'Check / Money order'),
  PaymentMethodOption(code: 'banktransfer', title: 'Bank Transfer'),
  PaymentMethodOption(code: 'free', title: 'No Payment Information Required'),
  PaymentMethodOption(code: 'ngeniusonline', title: 'Visa & MasterCard'),
  PaymentMethodOption(code: 'ngeniusonline_samsungpay', title: 'Samsung Pay'),
  PaymentMethodOption(code: 'tabby_installments', title: 'Tabby'),
  PaymentMethodOption(code: 'tamara_pay_now', title: 'Tamara'),
  PaymentMethodOption(
    code: 'payment_services_paypal_hosted_fields',
    title: 'Credit Card',
  ),
  PaymentMethodOption(code: 'braintree', title: 'Braintree'),
];

void main() {
  group('supportedPaymentMethods', () {
    test('Hub Market keeps only methods that complete on placeOrder', () {
      expect(
        _codes(supportedPaymentMethods(_all, BackendCapabilities.hubMarket)),
        ['cashondelivery', 'checkmo', 'banktransfer', 'free'],
      );
    });

    test('with payment sessions the gateways come back, web SDKs never', () {
      expect(
        _codes(
          supportedPaymentMethods(
            _all,
            const BackendCapabilities(gatewayPaymentSessions: true),
          ),
        ),
        [
          'cashondelivery',
          'checkmo',
          'banktransfer',
          'free',
          'ngeniusonline',
          'ngeniusonline_samsungpay',
          'tabby_installments',
          'tamara_pay_now',
        ],
      );
    });

    test('never adds a method', () {
      expect(supportedPaymentMethods(const [], BackendCapabilities.hubMarket),
          isEmpty);
    });
  });

  group('tabbyConfigProvider', () {
    test('asks nothing of a backend without tabbyConfig', () async {
      final repo = FakeCheckoutRepository(
        tabbyConfig: const TabbyConfig(enabled: true, currency: 'AED'),
      );
      final container = ProviderContainer(
        overrides: [checkoutRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      expect(await container.read(tabbyConfigProvider.future), isNull);
      expect(repo.calls, isEmpty);
    });

    test('reads it where the backend has one', () async {
      final repo = FakeCheckoutRepository(
        tabbyConfig: const TabbyConfig(enabled: true, currency: 'AED'),
      );
      final container = ProviderContainer(
        overrides: [
          checkoutRepositoryProvider.overrideWithValue(repo),
          backendCapabilitiesProvider.overrideWithValue(
            const BackendCapabilities(tabbyPromo: true),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(tabbyConfigProvider.future), isNotNull);
      expect(repo.calls, ['fetchTabbyConfig']);
    });
  });
}
