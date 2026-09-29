import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/address_rules.dart';
import 'package:hubmarket_app/features/account/domain/customer_address.dart';

void main() {
  group('postcodeRequiredFor', () {
    test("Hub Market's list doesn't cover the UAE, so AE needs a postcode", () {
      // storeConfig.optional_zip_countries on the live store.
      expect(postcodeRequiredFor('HK,IE,MO,PA,GB', 'AE'), isTrue);
    });

    test('a store that lists AE as optional needs none', () {
      expect(postcodeRequiredFor('HK, IE,AE,GB', 'ae'), isFalse);
    });

    test('no list at all means required (Magento semantics)', () {
      expect(postcodeRequiredFor(null, 'AE'), isTrue);
    });
  });

  group('CustomerAddress.toInput region', () {
    CustomerAddress address({int? regionId, String region = ''}) =>
        CustomerAddress(
          firstName: 'Layla',
          lastName: 'Hassan',
          telephone: '+971500000000',
          street: '1 Marina Walk',
          city: 'Dubai',
          postcode: '00000',
          region: region,
          regionId: regionId,
        );

    test('a store region goes out as region_id', () {
      expect(address(regionId: 1149).toInput()['region'], {'region_id': 1149});
    });

    test('without one, the emirate name goes out as free text', () {
      expect(address(region: 'Dubai').toInput()['region'], {'region': 'Dubai'});
    });

    test('a local picker id is never sent as a region_id', () {
      final input = address(regionId: -3, region: 'Dubai').toInput();
      expect(input['region'], {'region': 'Dubai'});
    });

    test('carries the postcode when there is one', () {
      expect(address(region: 'Dubai').toInput()['postcode'], '00000');
    });
  });
}
