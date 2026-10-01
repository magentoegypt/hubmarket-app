import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';

/// The delivery address on one line, in the order Figma 17 / 18b print it.
void main() {
  test('apartment, street, area, emirate, country', () {
    expect(
      shipToAddressLine(
        apartment: 'Apt 1204',
        street: 'Marina Gate 2',
        area: 'Dubai Marina',
        emirate: 'Dubai',
        country: 'UAE',
      ),
      'Apt 1204, Marina Gate 2, Dubai Marina, Dubai, UAE',
    );
  });

  test('blank parts are left out, and so is a part that repeats another', () {
    // An address saved without an area: the app derived "Dubai" from the
    // emirate, so city and emirate are the same word.
    expect(
      shipToAddressLine(
        street: 'Marina Gate 2',
        area: 'Dubai',
        emirate: 'dubai',
        country: 'UAE',
      ),
      'Marina Gate 2, Dubai, UAE',
    );
    expect(shipToAddressLine(street: '  Marina Gate 2 '), 'Marina Gate 2');
    expect(shipToAddressLine(), '');
  });

  test('the separator is the locale\'s comma', () {
    expect(
      shipToAddressLine(street: 'شارع 9', emirate: 'دبي', separator: '، '),
      'شارع 9، دبي',
    );
  });
}
