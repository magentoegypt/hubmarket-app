import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/domain/payment_wallet.dart';
import 'package:hubmarket_app/features/checkout/payments/native_payment_gateway.dart';
import 'package:hubmarket_app/features/checkout/payments/wallet_availability.dart';

const _apple = PaymentMethodOption(code: 'ngeniusonline_applepay', title: 'Apple Pay');
const _samsung = PaymentMethodOption(
  code: 'ngeniusonline_samsungpay',
  title: 'Samsung Pay',
);
const _card = PaymentMethodOption(
  code: 'ngeniusonline',
  title: 'Visa & MasterCard',
);
const _tabby = PaymentMethodOption(code: 'tabby_installments', title: 'Tabby');
const _cod = PaymentMethodOption(code: 'cashondelivery', title: 'COD');

/// Installs a `walletAvailability` handler on the real channel and removes it
/// after the test, so no handler leaks into the next one.
void _mockChannel(WidgetTester? _, Future<Object?>? Function(MethodCall) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(NativePaymentGateway.channel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativePaymentGateway.channel, null);
  });

  group('WalletAvailability.allows', () {
    test('card is always allowed, wallets follow their flag', () {
      const both = WalletAvailability(applePay: true, samsungPay: true);
      expect(both.allows(PaymentWallet.card), isTrue);
      expect(both.allows(PaymentWallet.applePay), isTrue);
      expect(both.allows(PaymentWallet.samsungPay), isTrue);

      // Card must survive even when nothing is available, or checkout would
      // lose its only universally usable method.
      expect(WalletAvailability.none.allows(PaymentWallet.card), isTrue);
      expect(WalletAvailability.none.allows(PaymentWallet.applePay), isFalse);
      expect(WalletAvailability.none.allows(PaymentWallet.samsungPay), isFalse);
    });
  });

  group('filterUnavailableWallets', () {
    test('drops only the unavailable wallets', () {
      final kept = filterUnavailableWallets(
        [_apple, _samsung, _card, _tabby, _cod],
        const WalletAvailability(applePay: true),
      );
      expect(kept, [_apple, _card, _tabby, _cod]);
    });

    test('drops both wallets when the device supports neither', () {
      final kept = filterUnavailableWallets(
        [_apple, _samsung, _card, _cod],
        WalletAvailability.none,
      );
      expect(kept, [_card, _cod]);
    });

    test('never filters the list to empty', () {
      // CheckoutState.shippingDone requires paymentMethods.isNotEmpty, so an
      // empty result would hide the whole payment step and dead-end checkout.
      // An unusable row that fails at the sheet beats no step 3 at all.
      final kept = filterUnavailableWallets(
        [_apple, _samsung],
        WalletAvailability.none,
      );
      expect(kept, [_apple, _samsung]);
    });

    test('passes an all-card list through untouched', () {
      final methods = [_card, _tabby, _cod];
      expect(
        filterUnavailableWallets(methods, WalletAvailability.none),
        methods,
      );
    });
  });

  group('WalletProbe.query', () {
    test('reads the native answer', () async {
      _mockChannel(null, (call) async {
        expect(call.method, 'walletAvailability');
        return <String, dynamic>{'applePay': true, 'samsungPay': false};
      });
      final availability = await const WalletProbe().query();
      expect(availability.applePay, isTrue);
      expect(availability.samsungPay, isFalse);
    });

    test('a missing native module means no wallets, not a crash', () async {
      // An older native binary (or any widget test without a handler) answers
      // MissingPluginException. That must hide the wallet rows and leave the
      // rest of checkout working, exactly as before this feature existed.
      _mockChannel(null, (call) async {
        throw MissingPluginException('no implementation for ${call.method}');
      });
      final availability = await const WalletProbe().query();
      expect(availability.applePay, isFalse);
      expect(availability.samsungPay, isFalse);
    });

    test('a platform error means no wallets', () async {
      _mockChannel(null, (call) async {
        throw PlatformException(code: 'SDK_ERROR', message: 'boom');
      });
      final availability = await const WalletProbe().query();
      expect(availability.applePay, isFalse);
      expect(availability.samsungPay, isFalse);
    });

    test('a partial or wrongly-typed map degrades to unavailable', () async {
      _mockChannel(null, (call) async => <String, dynamic>{'applePay': 'yes'});
      final availability = await const WalletProbe().query();
      expect(availability.applePay, isFalse);
      expect(availability.samsungPay, isFalse);
    });

    test('a null answer degrades to unavailable', () async {
      _mockChannel(null, (call) async => null);
      final availability = await const WalletProbe().query();
      expect(availability.applePay, isFalse);
      expect(availability.samsungPay, isFalse);
    });
  });
}
