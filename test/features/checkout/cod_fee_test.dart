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
import 'package:hubmarket_app/features/checkout/payments/wallet_availability.dart';
import 'package:hubmarket_app/features/checkout/presentation/checkout_controller.dart';

import '../../support/fakes.dart';

/// Cash on Delivery carries a flat handling fee the server folds into
/// `grand_total` (CL042-DEV43). The app reads that total; it must re-read it
/// once a method is on the quote, or it quotes the shopper less than they are
/// charged.
const _cod = PaymentMethodOption(code: 'cashondelivery', title: 'COD');
const _card = PaymentMethodOption(code: 'ngeniusonline', title: 'Visa & MC');

const _aed = 'AED';
const _subtotal = Money(amount: 69, currency: _aed);
const _withoutFee = Money(amount: 79, currency: _aed); // 69 + 10 shipping
const _withFee = Money(amount: 89, currency: _aed); // + 10 COD fee
const _fee = Money(amount: 10, currency: _aed);

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

/// A cart whose totals follow the payment method, the way the store's do:
/// the fee appears on `cashondelivery` and is removed again on anything else.
class _CodCartRepo extends FakeCartRepository {
  String? method;

  /// Makes the totals re-read fail, as a dropped connection would.
  bool failGetCart = false;

  bool get _codSelected => method == 'cashondelivery';

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
            grandTotal: _codSelected ? _withFee : _withoutFee,
            subtotal: _subtotal,
            // Money, never null: zero when it does not apply.
            codFee: _codSelected
                ? _fee
                : const Money(amount: 0, currency: _aed),
          ),
        );
}

/// Applies the method to the cart, as storing it on the quote does server-side.
class _CodCheckoutRepo extends FakeCheckoutRepository {
  _CodCheckoutRepo(this.cart);

  final _CodCartRepo cart;

  @override
  Future<bool> setPaymentMethod(
    String cartId,
    String code, {
    String? publicHash,
    bool saveCard = false,
  }) async {
    cart.method = code;
    return super.setPaymentMethod(
      cartId,
      code,
      publicHash: publicHash,
      saveCard: saveCard,
    );
  }
}

Future<ProviderContainer> _seeded(
  _CodCartRepo cart,
  _CodCheckoutRepo checkout,
) async {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      cartRepositoryProvider.overrideWithValue(cart),
      checkoutRepositoryProvider.overrideWithValue(checkout),
      walletAvailabilityProvider.overrideWith(
        (ref) async => WalletAvailability.none,
      ),
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
  group('COD fee', () {
    test('choosing COD re-reads the total instead of quoting the stale one', () async {
      final cart = _CodCartRepo();
      final container = await _seeded(cart, _CodCheckoutRepo(cart));
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectPayment(_cod);

      // 89, not the 79 read before any method was on the quote. Quoting 79 is
      // the bug: the Place Order button renders this and the shopper is
      // charged 89.
      expect(container.read(checkoutControllerProvider).grandTotal, _withFee);
    });

    test('switching away from COD drops the total back', () async {
      final cart = _CodCartRepo();
      final container = await _seeded(cart, _CodCheckoutRepo(cart));
      final checkout = container.read(checkoutControllerProvider.notifier);

      await checkout.selectPayment(_cod);
      await checkout.selectPayment(_card);

      expect(container.read(checkoutControllerProvider).grandTotal, _withoutFee);
    });

    test('the refreshed cart carries the fee for the summary row', () async {
      final cart = _CodCartRepo();
      final container = await _seeded(cart, _CodCheckoutRepo(cart));
      await container
          .read(checkoutControllerProvider.notifier)
          .selectPayment(_cod);

      final totals = container.read(cartControllerProvider).cart.totals;
      expect(totals.hasCodFee, isTrue);
      expect(totals.codFee, _fee);
    });

    test('a failed refresh keeps the method selectable', () async {
      final cart = _CodCartRepo();
      final checkoutRepo = _CodCheckoutRepo(cart);
      final container = await _seeded(cart, checkoutRepo);
      final checkout = container.read(checkoutControllerProvider.notifier);

      // The charged amount comes from the server at placeOrder either way, so
      // a totals refresh that fails must not block choosing a method.
      cart.failGetCart = true;
      final ok = await checkout.selectPayment(_cod);

      expect(ok, isTrue);
      expect(container.read(checkoutControllerProvider).selectedPayment, _cod);
    });
  });

  group('CartTotals.hasCodFee', () {
    test('is false for the zero the server sends when it does not apply', () {
      const totals = CartTotals(codFee: Money(amount: 0, currency: _aed));
      expect(totals.hasCodFee, isFalse);
    });

    test('is false when the field is absent', () {
      expect(const CartTotals().hasCodFee, isFalse);
    });

    test('is true for a real fee', () {
      const totals = CartTotals(codFee: _fee);
      expect(totals.hasCodFee, isTrue);
    });
  });
}
