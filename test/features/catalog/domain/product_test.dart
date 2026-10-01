import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';

void main() {
  group('Money', () {
    test('formats AED with Western digits and two decimals', () {
      expect(
        const Money(amount: 199, currency: 'AED').formatted(),
        'AED 199',
      );
      expect(
        const Money(amount: 1250.5, currency: 'AED').formatted(),
        'AED 1,250.50',
      );
    });
  });

  group('Product pricing', () {
    test('detects a genuine discount', () {
      const product = Product(
        sku: 's',
        name: 'n',
        urlKey: 'u',
        regularPrice: Money(amount: 250, currency: 'AED'),
        finalPrice: Money(amount: 199, currency: 'AED'),
      );
      expect(product.isOnSale, isTrue);
      expect(product.discountPercent, 20); // (250-199)/250 = 20.4% -> 20
    });

    test('no discount when final equals regular', () {
      const product = Product(
        sku: 's',
        name: 'n',
        urlKey: 'u',
        regularPrice: Money(amount: 300, currency: 'AED'),
        finalPrice: Money(amount: 300, currency: 'AED'),
      );
      expect(product.isOnSale, isFalse);
      expect(product.discountPercent, isNull);
    });

    test('sub-0.5% markdown does not render a "-0%" badge', () {
      // AED 400 -> 399 is a real 0.25% markdown that rounds to 0%; the badge
      // must be hidden (discountPercent null) even though a struck price shows.
      const product = Product(
        sku: 's',
        name: 'n',
        urlKey: 'u',
        regularPrice: Money(amount: 400, currency: 'AED'),
        finalPrice: Money(amount: 399, currency: 'AED'),
      );
      expect(product.isOnSale, isTrue);
      expect(product.discountPercent, isNull);
    });
  });
}
