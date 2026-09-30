import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/store_credit/domain/store_credit.dart';

import '../../support/store_credit_fakes.dart';

/// What the 20d "Buy credit" card lets a customer buy.
void main() {
  group('StoreCreditTopUp', () {
    test('presets are bought as they are, nothing else without a range', () {
      final offer = sampleTopUp();

      expect(offer.allowsCustomAmount, isFalse);
      expect(offer.accepts(50), isTrue);
      expect(offer.accepts(100), isTrue);
      expect(offer.accepts(250), isTrue);
      expect(offer.accepts(75), isFalse);
      expect(offer.presetFor(100)!.sku, 'hm-credit-100');
      expect(offer.presetFor(75), isNull);
      expect(offer.currency, 'AED');
    });

    test('a custom amount is a whole number within the range', () {
      final offer = sampleTopUp(custom: true);

      expect(offer.allowsCustomAmount, isTrue);
      expect(offer.acceptsCustom(10), isTrue);
      expect(offer.acceptsCustom(1000), isTrue);
      expect(offer.acceptsCustom(150), isTrue);
      expect(offer.acceptsCustom(9), isFalse);
      expect(offer.acceptsCustom(1001), isFalse);
      expect(offer.acceptsCustom(12.5), isFalse);
      expect(offer.acceptsCustom(double.nan), isFalse);
      expect(offer.accepts(150), isTrue);
    });

    test('the price is the preset\'s, or the amount over the rate', () {
      expect(sampleTopUp(price100: 90).priceOf(100)!.amount, 90);
      expect(sampleTopUp(custom: true).priceOf(150)!.amount, 150);
      final bonus = StoreCreditTopUp(
        sku: 'hm-credit-any',
        min: aedCredit(1),
        max: aedCredit(500),
        creditRate: 1.5,
      );
      expect(bonus.priceOf(40)!.amount, 26.67);
      expect(bonus.priceOf(0.5), isNull);
      expect(sampleTopUp().priceOf(75), isNull);
    });

    test('the card opens on the middle preset, else the smallest amount', () {
      // Figma 20d: AED 100 of 50 / 100 / 250 is chosen.
      expect(sampleTopUp().initialAmount, 100);
      expect(
        StoreCreditTopUp(
          sku: 'hm-credit-any',
          min: aedCredit(10),
          max: aedCredit(1000),
          creditRate: 1,
        ).initialAmount,
        10,
      );
    });
  });
}
