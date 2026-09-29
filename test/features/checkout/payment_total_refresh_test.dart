import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/cart/domain/cart.dart';
import 'package:hubmarket_app/features/cart/presentation/cart_controller.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/checkout/data/checkout_repository.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/checkout/presentation/checkout_controller.dart';

import '../../support/fakes.dart';

/// The grand total is re-read once a payment method is on the quote. The one
/// captured at the shipping step predates any method, so a method-dependent
/// charge (a payment-surcharge extension) would otherwise make the summary and
/// the Place Order button quote less than the shopper is charged.
const _cod = PaymentMethodOption(code: 'cashondelivery', title: 'COD');
const _checkmo = PaymentMethodOption(code: 'checkmo', title: 'Check / Money order');

const _aed = 'AED';
const _subtotal = Money(amount: 69, currency: _aed);
const _plain = Money(amount: 79, currency: _aed); // 69 + 10 shipping
const _surcharged = Money(amount: 84, currency: _aed); // + 5 on checkmo

const _address = <String, dynamic>{
  'address': {
    'firstname': 'Layla',
    'lastname': 'Hassan',
    'telephone': '0500000000',
    'street': ['1 Marina Walk'],
    'city': 'Dubai',
    'country_code': 'AE',
  },
};

/// A cart whose grand total follows the payment method, the way a store with
/// a surcharge on one method behaves.
class _SurchargeCartRepo extends FakeCartRepository {
  String? method;

  /// Makes the totals re-read fail, as a dropped connection would.
  bool failGetCart = false;

  @override
  Future<Cart> getCart(String cartId) async => failGetCart
      ? throw const Failure(FailureKind.unknown)
      : Cart(
          id: cartId,
          totalQuantity: 1,
          items: const [
            CartItem(
              uid: 'i1',
              sku: 'SKU1',
              name: 'SKU1',
              quantity: 1,
              rowTotal: _subtotal,
            ),
          ],
          totals: CartTotals(
            grandTotal: method == 'checkmo' ? _surcharged : _plain,
            subtotal: _subtotal,
          ),
        );
}

/// Applies the method to the cart, as storing it on the quote does server-side.
class _MethodCheckoutRepo extends FakeCheckoutRepository {
  _MethodCheckoutRepo(this.cart)
    : super(paymentMethods: const [_cod, _checkmo]);

  final _SurchargeCartRepo cart;

  @override
  Future<void> setPaymentMethod(String cartId, String code) async {
    cart.method = code;
    return super.setPaymentMethod(cartId, code);
  }
}

Future<ProviderContainer> _seeded(
  _SurchargeCartRepo cart,
  _MethodCheckoutRepo checkout,
) async {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(cart),
      checkoutRepositoryProvider.overrideWithValue(checkout),
    ],
  );
  addTearDown(container.dispose);
  container.listen(cartControllerProvider, (_, __) {});
  container.listen(authControllerProvider, (_, __) {});
  container.listen(checkoutControllerProvider, (_, __) {});
  await container.read(cartControllerProvider.notifier).addToCart(sku: 'SKU1');
  await container
      .read(checkoutControllerProvider.notifier)
      .submitAddress(
        email: 'shopper@example.com',
        shippingAddress: _address,
        lastname: 'Hassan',
        telephone: '0500000000',
        isGuest: false,
      );
  return container;
}

void main() {
  group('grand total after choosing a payment method', () {
    test('re-reads the total instead of quoting the stale one', () async {
      final cart = _SurchargeCartRepo();
      final container = await _seeded(cart, _MethodCheckoutRepo(cart));
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectPayment(_checkmo);

      // 84, not the 79 read before any method was on the quote.
      expect(container.read(checkoutControllerProvider).grandTotal, _surcharged);
    });

    test('switching methods follows the total back down', () async {
      final cart = _SurchargeCartRepo();
      final container = await _seeded(cart, _MethodCheckoutRepo(cart));
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectPayment(_checkmo);
      await checkout.selectPayment(_cod);

      expect(container.read(checkoutControllerProvider).grandTotal, _plain);
    });

    test('a failed refresh keeps the method selectable', () async {
      final cart = _SurchargeCartRepo();
      final container = await _seeded(cart, _MethodCheckoutRepo(cart));
      final checkout = container.read(checkoutControllerProvider.notifier);

      // The charged amount comes from the server at placeOrder either way, so
      // a totals refresh that fails must not block choosing a method.
      cart.failGetCart = true;
      final ok = await checkout.selectPayment(_cod);

      expect(ok, isTrue);
      expect(container.read(checkoutControllerProvider).selectedPayment, _cod);
    });
  });
}
