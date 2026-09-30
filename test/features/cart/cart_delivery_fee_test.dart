import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/cart/data/cart_repository.dart';
import 'package:hubmarket_app/features/marketplace/marketplace_features.dart';

import '../../support/marketplace_fakes.dart';

/// `cart` data with one line, a subtotal and total, and the given
/// `shipping_addresses`.
Map<String, dynamic> _cart(List<Map<String, dynamic>> shippingAddresses) => {
  '__typename': 'Cart',
  'id': 'cart-1',
  'total_quantity': 1,
  'items': [
    {
      '__typename': 'SimpleCartItem',
      'uid': 'line-sofa',
      'quantity': 1,
      'product': {'__typename': 'SimpleProduct', 'sku': 'SOFA', 'name': 'Sofa'},
    },
  ],
  'shipping_addresses': shippingAddresses,
  'prices': {
    '__typename': 'CartPrices',
    'grand_total': {'__typename': 'Money', 'value': 435.0, 'currency': 'AED'},
    'subtotal_including_tax': {
      '__typename': 'Money',
      'value': 425.0,
      'currency': 'AED',
    },
  },
};

Map<String, dynamic> _address(double? fee) => {
  '__typename': 'ShippingCartAddress',
  'selected_shipping_method': fee == null
      ? null
      : {
          '__typename': 'SelectedShippingMethod',
          'amount': {'__typename': 'Money', 'value': fee, 'currency': 'AED'},
        },
};

Future<CartRepository> _repository(Map<String, dynamic> cart) async {
  final server = RecordingGraphQLClient((_, __) => {'cart': cart});
  return CartRepository(
    server.client,
    marketplace: const FixedMarketplaceGate(),
  );
}

void main() {
  test('the cart asks for the delivery method chosen at checkout', () async {
    final server = RecordingGraphQLClient((_, __) => {'cart': _cart([])});
    await CartRepository(
      server.client,
      marketplace: const FixedMarketplaceGate(),
    ).getCart('cart-1');

    expect(server.documents.single, contains('selected_shipping_method'));
  });

  test('a chosen delivery method gives the cart its fee', () async {
    final cart = await (await _repository(
      _cart([_address(10)]),
    )).getCart('cart-1');

    expect(cart.totals.shipping?.amount, 10);
    expect(cart.totals.shipping?.currency, 'AED');
    expect(cart.totals.grandTotal?.amount, 435);
  });

  test('no address, or no method chosen yet, leaves the fee unknown', () async {
    final none = await (await _repository(_cart([]))).getCart('cart-1');
    final notChosen = await (await _repository(
      _cart([_address(null)]),
    )).getCart('cart-1');

    expect(none.totals.shipping, isNull);
    expect(notChosen.totals.shipping, isNull);
  });
}
