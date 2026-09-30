import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/saved_card.dart';

import '../../support/hubapp_fakes.dart';

Map<String, dynamic> _token({
  String hash = 'abc123',
  String type = 'card',
  String? details = '{"type":"VI","maskedCC":"1111","expirationDate":"12/2028"}',
}) => {
  'public_hash': hash,
  'payment_method_code': 'ngeniusonline',
  'type': type,
  'details': details,
};

void main() {
  group('SavedCard.fromToken', () {
    test('parses the Magento card details blob', () {
      final card = SavedCard.fromToken(_token())!;

      expect(card.publicHash, 'abc123');
      expect(card.brandCode, 'VI');
      expect(card.brandLabel, 'Visa');
      expect(card.last4, '1111');
      expect(card.maskedNumber, '•••• 1111');
      expect(card.expiryMonth, 12);
      expect(card.expiryYear, 2028);
      expect(card.expiryLabel, '12/28');
    });

    test('keeps only the last four of a fully masked pan', () {
      final card = SavedCard.fromToken(
        _token(details: '{"type":"MC","maskedCC":"XXXX-XXXX-XXXX-4444"}'),
      )!;

      expect(card.last4, '4444');
      expect(card.brandLabel, 'Mastercard');
      // No expiry stored — the row still renders, and is not treated as expired.
      expect(card.expiryLabel, isNull);
      expect(card.isExpired, isFalse);
    });

    test('accepts two-digit years and datetime expiries', () {
      expect(
        SavedCard.fromToken(
          _token(details: '{"type":"VI","maskedCC":"1111","expirationDate":"03/27"}'),
        )!.expiryYear,
        2027,
      );
      final iso = SavedCard.fromToken(
        _token(
          details:
              '{"type":"VI","maskedCC":"1111","expirationDate":"2029-07-01 00:00:00"}',
        ),
      )!;
      expect((iso.expiryMonth, iso.expiryYear), (7, 2029));
    });

    test('survives a malformed or missing details blob', () {
      // A vault row is written by a gateway integration we do not own, so a
      // broken `details` must degrade to a renderable card, never throw.
      for (final details in <String?>[null, '', 'not json', '["a"]', '{}']) {
        final card = SavedCard.fromToken(_token(details: details));
        expect(card, isNotNull, reason: 'details=$details');
        expect(card!.maskedNumber, '••••');
        expect(card.brandLabel, 'Card');
      }
    });

    test('drops rows the picker could not act on', () {
      expect(SavedCard.fromToken(_token(hash: '')), isNull);
      // `type` is the token type, not the brand: an `account` token is PayPal-
      // shaped and has no card to show.
      expect(SavedCard.fromToken(_token(type: 'account')), isNull);
    });

    test('is expired only after the last day of the expiry month', () {
      final card = SavedCard.fromToken(
        _token(details: '{"type":"VI","maskedCC":"1111","expirationDate":"06/2026"}'),
      )!;

      expect(card.isExpiredAt(DateTime(2026, 6, 30, 23, 59)), isFalse);
      expect(card.isExpiredAt(DateTime(2026, 7)), isTrue);
    });

    test('falls back to the raw code for an unmapped scheme', () {
      final card = SavedCard.fromToken(
        _token(details: '{"type":"ZZ","maskedCC":"9999"}'),
      )!;
      expect(card.brandLabel, 'ZZ');
    });
  });

  group('AccountRepository.fetchSavedCards', () {
    test('lists the cards of any vaulting gateway, not only N-Genius', () async {
      Map<String, dynamic> row(String hash, String code, {String? type}) => {
        ..._token(hash: hash, type: type ?? 'card'),
        'payment_method_code': code,
      };
      final repo = AccountRepository(
        fakeHubAppClient({
          'CustomerPaymentTokens': {
            'customerPaymentTokens': {
              'items': [
                row('aps', 'payment_services_paypal_vault'),
                row('bt', 'braintree_cc_vault'),
                row('pp', 'braintree_paypal_vault', type: 'account'),
              ],
            },
          },
        }),
      );

      final cards = await repo.fetchSavedCards();
      // Cards only: a PayPal account token is not a card to list.
      expect(cards.map((c) => c.publicHash), ['aps', 'bt']);
    });
  });
}
