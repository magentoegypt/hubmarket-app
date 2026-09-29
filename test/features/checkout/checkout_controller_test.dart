import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/checkout_controller.dart';

import '../../support/fakes.dart';

ProviderContainer _container(FakeCheckoutRepository repo) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(FakeCartRepository()),
      checkoutRepositoryProvider.overrideWithValue(repo),
    ],
  );
  addTearDown(container.dispose);
  container.listen(cartControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  container.listen(checkoutControllerProvider, (_, __) {});
  return container;
}

/// Seeds a guest cart so the checkout controller has a non-empty cart id.
Future<ProviderContainer> _seededContainer(FakeCheckoutRepository repo) async {
  final container = _container(repo);
  await container.read(cartControllerProvider.notifier).addToCart(sku: 'SKU1');
  return container;
}

const _address = <String, dynamic>{
  'firstname': 'Layla',
  'lastname': 'Hassan',
  'telephone': '0500000000',
  'street': ['1 Marina Walk'],
  'city': 'Dubai',
  'country_code': 'AE',
};

/// A newly entered address: the literal, which Magento may save to the book.
const _newAddress = <String, dynamic>{'address': _address};

/// A saved address referenced by id — never a literal, so Magento's
/// save_in_address_book default cannot duplicate it.
const _savedAddress = <String, dynamic>{'customer_address_id': 42};

void main() {
  group('CheckoutController', () {
    test('a saved address reaches the repo by id, with no address literal', () async {
      // The address-book duplication guard at the plumbing level: whatever the
      // screen builds must arrive at setShippingAddressesOnCart untouched. An
      // `address` key here means Magento would save a copy of an address the
      // customer already has.
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      final ok = await checkout.submitAddress(
        email: '',
        shippingAddress: _savedAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: false,
      );

      expect(ok, isTrue);
      expect(repo.lastAddress, _savedAddress);
      expect(repo.lastAddress!.containsKey('address'), isFalse);
      // The phone still tracks, even though the input map no longer carries it.
      expect(
        container.read(checkoutControllerProvider).submittedPhone,
        isNotEmpty,
      );
    });

    test('a guest places a cash-on-delivery order end to end (Hub Market)',
        () async {
      // What this store can actually do today: its available_payment_methods
      // may still list an online method (Tabby here), but the app completes
      // only offline ones, so cash on delivery is offered, pre-selected, and
      // the order completes on placeOrder with no payment step.
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      final addressOk = await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );
      expect(addressOk, isTrue);
      var state = container.read(checkoutControllerProvider);
      expect(state.addressDone, isTrue);
      expect(repo.guestEmail, 'guest@example.com');

      // Address → default shipping → payments → COD, all from one submit.
      state = container.read(checkoutControllerProvider);
      expect(state.shippingDone, isTrue);
      expect(state.grandTotal?.amount, 219);
      expect([for (final m in state.paymentMethods) m.code], ['cashondelivery']);
      expect(state.selectedPayment?.code, 'cashondelivery');
      // Guest OTP is off on this store, so nothing gates Place Order.
      expect(state.guestOtpVerified, isFalse);

      final result = await checkout.placeOrder();
      expect(result, isNotNull);
      expect(result!.orderNumber, '000000123');
      expect(container.read(checkoutControllerProvider).isBusy, isFalse);

      expect(repo.calls, [
        'setGuestEmail',
        'setShippingAddress',
        'setShippingMethod:flatrate|flatrate',
        'setBillingSameAsShipping',
        'setPaymentMethod:cashondelivery',
        'placeOrder',
      ]);
      // The order consumed the cart.
      expect(container.read(cartControllerProvider).cart.id, isEmpty);
    });

    test('online methods are dropped, offline ones kept in backend order',
        () async {
      // `is_deferred` marks an online integration: a card gateway, a wallet,
      // BNPL, PayPal via Payment Services. None completes on placeOrder, so
      // offering one would leave the order unpaid.
      final repo = FakeCheckoutRepository(
        paymentMethods: const [
          PaymentMethodOption(
            code: 'ngeniusonline',
            title: 'Visa & MasterCard',
            isOnline: true,
          ),
          PaymentMethodOption(code: 'checkmo', title: 'Check / Money order'),
          PaymentMethodOption(
            code: 'payment_services_paypal_hosted_fields',
            title: 'Credit Card',
            isOnline: true,
          ),
          PaymentMethodOption(code: 'cashondelivery', title: 'Cash On Delivery'),
        ],
      );
      final container = await _seededContainer(repo);
      await container
          .read(checkoutControllerProvider.notifier)
          .submitAddress(
            email: 'guest@example.com',
            shippingAddress: _newAddress,
            lastname: 'Hassan',
            telephone: '0500000000',
            isGuest: true,
          );

      final state = container.read(checkoutControllerProvider);
      expect(
        [for (final m in state.paymentMethods) m.code],
        ['checkmo', 'cashondelivery'],
      );
      // Cash on delivery stays the default wherever the backend lists it.
      expect(state.selectedPayment?.code, 'cashondelivery');
    });

    test(
      'does not set the guest email for an authenticated customer',
      () async {
        final repo = FakeCheckoutRepository();
        final container = await _seededContainer(repo);
        final checkout = container.read(checkoutControllerProvider.notifier);

        await checkout.submitAddress(
          email: 'layla@example.com',
          shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
          isGuest: false,
        );

        expect(repo.guestEmail, isNull);
        expect(repo.lastAddress, _newAddress);
      },
    );

    test('returns false and records the error when a step fails', () async {
      final repo = FakeCheckoutRepository(fail: true);
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      final ok = await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );

      expect(ok, isFalse);
      final state = container.read(checkoutControllerProvider);
      expect(state.error, isNotNull);
      expect(state.isBusy, isFalse);
      expect(state.addressDone, isFalse);
    });

    test('reset() clears progress so the next checkout starts clean', () async {
      // Regression: the controller is a session-wide singleton. Without a reset
      // on checkout entry, a second checkout (or a checkout after logout)
      // reused the previous order's shipping/payment/total — a stale grand
      // total, and placeOrder failing because shipping/payment were treated as
      // already-set on the new cart.
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );
      var state = container.read(checkoutControllerProvider);
      await checkout.selectShipping(state.shippingMethods.first);
      state = container.read(checkoutControllerProvider);
      await checkout.selectPayment(state.paymentMethods.first);
      // Sanity: the controller is now carrying full checkout progress.
      state = container.read(checkoutControllerProvider);
      expect(state.paymentDone, isTrue);
      expect(state.grandTotal, isNotNull);

      checkout.reset();

      state = container.read(checkoutControllerProvider);
      expect(state.addressDone, isFalse);
      expect(state.shippingDone, isFalse);
      expect(state.paymentDone, isFalse);
      expect(state.shippingMethods, isEmpty);
      expect(state.paymentMethods, isEmpty);
      expect(state.selectedShipping, isNull);
      expect(state.selectedPayment, isNull);
      expect(state.grandTotal, isNull);
      expect(state.email, isEmpty);
      expect(state.isGuest, isFalse);
    });

    test('submitAddress is a no-op without a cart', () async {
      // No addToCart → cart id stays empty → checkout cannot proceed.
      final repo = FakeCheckoutRepository();
      final container = _container(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      final ok = await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );

      expect(ok, isFalse);
      expect(repo.lastAddress, isNull);
    });
  });

  group('CheckoutController — guest OTP', () {
    test('submitAddress records the normalized submitted phone', () async {
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000', // telephone '0500000000'
        isGuest: true,
      );

      expect(
        container.read(checkoutControllerProvider).submittedPhone,
        '+971500000000',
      );
    });

    test('the code goes to, and is checked for, the submitted phone', () async {
      // Vnecoms' checkout OTP is phone-bound (customerCheckoutSendOtp /
      // customerCheckoutVerifyOtp take {mobile}), not cart-bound.
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );
      await checkout.requestGuestOtp();
      expect(repo.guestOtpPhone, '+971500000000');
      expect(repo.guestOtpResend, isFalse);

      await checkout.requestGuestOtp(resend: true);
      expect(repo.guestOtpResend, isTrue);

      await checkout.verifyGuestOtp('123456');
      expect(repo.guestOtpPhone, '+971500000000');
      expect(repo.guestOtpCode, '123456');
      expect(
        container.read(checkoutControllerProvider).guestOtpVerified,
        isTrue,
      );
    });

    test('no code is sent before a phone was submitted', () async {
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);

      await expectLater(
        container.read(checkoutControllerProvider.notifier).requestGuestOtp(),
        throwsA(isA<Object>()),
      );
      expect(repo.guestOtpPhone, isNull);
    });

    test('verifyGuestOtp surfaces a wrong-code failure and stays unverified',
        () async {
      final repo = FakeCheckoutRepository(guestOtpVerifyFails: true);
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );
      await expectLater(
        checkout.verifyGuestOtp('000000'),
        throwsA(isA<Object>()),
      );
      expect(
        container.read(checkoutControllerProvider).guestOtpVerified,
        isFalse,
      );
    });

    test('re-submitting the same phone keeps verification; a new phone resets it',
        () async {
      final repo = FakeCheckoutRepository();
      final container = await _seededContainer(repo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: _newAddress,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );
      await checkout.verifyGuestOtp('123456');
      expect(
        container.read(checkoutControllerProvider).guestOtpVerified,
        isTrue,
      );

      // Same phone, edited street → verification is kept.
      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: <String, dynamic>{
          'address': {..._address, 'street': ['2 New Street']},
        },
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: true,
      );
      expect(
        container.read(checkoutControllerProvider).guestOtpVerified,
        isTrue,
      );

      // Different phone → verification is reset.
      await checkout.submitAddress(
        email: 'guest@example.com',
        shippingAddress: <String, dynamic>{
          'address': {..._address, 'telephone': '0521111111'},
        },
        lastname: 'Hassan',
        telephone: '0521111111',
        isGuest: true,
      );
      expect(
        container.read(checkoutControllerProvider).guestOtpVerified,
        isFalse,
      );
    });
  });
}
