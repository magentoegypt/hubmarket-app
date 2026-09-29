import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';
import 'package:hubmarket_app/features/checkout/domain/shipping_address_input.dart';

const _saved = CustomerAddress(
  id: 42,
  firstName: 'Layla',
  lastName: 'Hassan',
  telephone: '+971500000000',
  street: '1 Marina Walk',
  city: 'Dubai',
  regionId: 1149,
  countryCode: 'AE',
  defaultShipping: true,
);

void main() {
  group('ShippingAddressInput.saved', () {
    test('references the address book id', () {
      expect(ShippingAddressInput.saved(_saved), {'customer_address_id': 42});
    });

    test('carries NO address literal', () {
      // The regression guard. Magento's SetShippingAddressesOnCart forces
      // save_in_address_book = true whenever an `address` arrives without a
      // customer_address_id and without the flag, so a literal here silently
      // duplicated the customer's address on every checkout — the account used
      // for QA had accumulated eight identical copies.
      final input = ShippingAddressInput.saved(_saved);
      expect(input.containsKey('address'), isFalse);
      expect(input.keys, ['customer_address_id']);
    });

    test('sends nothing that could be re-saved, even for a rich address', () {
      // Every field Magento would need to *create* an address must be absent,
      // not merely ignored.
      final input = ShippingAddressInput.saved(_saved);
      for (final key in [
        'firstname',
        'lastname',
        'telephone',
        'street',
        'city',
        'region_id',
        'country_code',
        'save_in_address_book',
      ]) {
        expect(
          input.containsKey(key),
          isFalse,
          reason: '$key must not be sent for a saved address',
        );
      }
    });
  });

  group('ShippingAddressInput.fresh', () {
    test('wraps a newly entered address as an address literal', () {
      const address = <String, dynamic>{
        'firstname': 'Layla',
        'lastname': 'Hassan',
        'telephone': '+971500000000',
        'street': ['1 Marina Walk'],
        'city': 'Dubai',
        'country_code': 'AE',
      };
      final input = ShippingAddressInput.fresh(address);
      expect(input, {'address': address});
      // Deliberately no customer_address_id and no save_in_address_book: a
      // shopper who types an address at checkout expects it to be saved, so
      // Magento's default is the behaviour we want here.
      expect(input.containsKey('customer_address_id'), isFalse);
    });
  });
}
