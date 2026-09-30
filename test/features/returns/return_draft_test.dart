import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/return_draft.dart';
import 'package:hubmarket_app/features/returns/domain/return_photo.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';

import '../../support/returns_fakes.dart';

ReturnableItem _line(int id) =>
    kTwoSellerOrder.items.firstWhere((i) => i.orderItemId == id);

void main() {
  final tShirt = _line(501); // loly store, 2 returnable
  final bag = _line(502); // loly store, already in R-000031
  final sofa = _line(503); // MIA CO, 1 returnable

  group('eligibility', () {
    test('a line with nothing left to return cannot be ticked', () {
      const draft = ReturnDraft(order: kTwoSellerOrder);
      expect(draft.availabilityOf(bag), LineAvailability.unavailable);
      expect(identical(draft.toggle(bag), draft), isTrue);
      expect(draft.availabilityOf(tShirt), LineAvailability.available);
      expect(draft.availabilityOf(sofa), LineAvailability.available);
    });

    test('a ticked line starts at everything that is left', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder).toggle(tShirt);
      expect(draft.availabilityOf(tShirt), LineAvailability.selected);
      expect(draft.quantities, {501: 2});
      expect(draft.toggle(tShirt).quantities, isEmpty);
    });
  });

  group('one seller per return', () {
    test('ticking a line blocks the other sellers’ lines', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder).toggle(tShirt);
      expect(draft.sellerKey, returnSellerKey(kLolyStore));
      expect(draft.seller?.name, 'loly store');
      expect(draft.availabilityOf(sofa), LineAvailability.otherSeller);
      // Ticking it anyway changes nothing.
      expect(draft.toggle(sofa).quantities, {501: 2});
    });

    test('unticking the last line frees every seller again', () {
      final draft = const ReturnDraft(
        order: kTwoSellerOrder,
      ).toggle(tShirt).toggle(tShirt);
      expect(draft.sellerKey, isNull);
      expect(draft.availabilityOf(sofa), LineAvailability.available);
      expect(draft.toggle(sofa).quantities, {503: 1});
    });

    test('sellers are told apart the way the server groups lines', () {
      expect(returnSellerKey(kLolyStore), isNot(returnSellerKey(kMiaCo)));
      expect(
        returnSellerKey(const HmSellerSummary(name: 'X', vendorEntityId: 12)),
        returnSellerKey(kLolyStore),
      );
      expect(returnSellerKey(kHubMarket), 'hub');
      // Lines whose seller wasn't sent share one group.
      expect(returnSellerKey(null), returnSellerKey(null));
    });
  });

  group('quantity limits', () {
    test('partial returns: 1 up to the returnable quantity', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder).toggle(tShirt);
      expect(ReturnDraft.minQuantity(tShirt, kSampleReturnConfig), 1);
      expect(draft.setQuantity(tShirt, 1, kSampleReturnConfig).quantities, {
        501: 1,
      });
      expect(draft.setQuantity(tShirt, 0, kSampleReturnConfig).quantities, {
        501: 1,
      });
      expect(draft.setQuantity(tShirt, 5, kSampleReturnConfig).quantities, {
        501: 2,
      });
    });

    test('without partial returns a line goes back whole', () {
      const config = ReturnConfig(partialQuantityAllowed: false);
      final draft = const ReturnDraft(order: kTwoSellerOrder).toggle(tShirt);
      expect(ReturnDraft.minQuantity(tShirt, config), 2);
      expect(draft.setQuantity(tShirt, 1, config).quantities, {501: 2});
    });

    test('an unticked line has no quantity to set', () {
      const draft = ReturnDraft(order: kTwoSellerOrder);
      expect(
        draft.setQuantity(tShirt, 1, kSampleReturnConfig).quantities,
        isEmpty,
      );
    });
  });

  group('refund cap', () {
    test('sums the server’s unit prices × units ticked', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder).toggle(tShirt);
      expect(draft.needsFallbackPrices, isFalse);
      expect(draft.refundCap(), 86);
      expect(
        draft.setQuantity(tShirt, 1, kSampleReturnConfig).refundCap(),
        43,
      );
      // The server's figure wins over any other.
      expect(draft.refundCap(const {501: 99}), 86);
    });

    test('rounds down to the cent, as the server reports the cap', () {
      const order = ReturnableOrder(
        number: '1',
        createdAt: '',
        statusLabel: '',
        items: [
          ReturnableItem(
            orderItemId: 9,
            name: 'Kettle',
            qtyOrdered: 3,
            qtyReturnable: 2,
            unitPrice: Money(amount: 33.335, currency: 'AED'),
          ),
        ],
      );
      final draft = const ReturnDraft(order: order).toggle(order.items.single);
      expect(draft.refundCap(), 66.67);
    });

    test('a server without unit prices falls back to the core order’s', () {
      final line = kLegacyOrder.items.single;
      final draft = const ReturnDraft(order: kLegacyOrder).toggle(line);
      expect(draft.needsFallbackPrices, isTrue);
      expect(draft.refundCap(), isNull);
      expect(draft.refundCap(const {470: 55}), 165);
      expect(ReturnDraft.unitRefund(line, const {470: 55}), 55);
    });

    test('unknown when nothing is ticked', () {
      const draft = ReturnDraft(order: kTwoSellerOrder);
      expect(draft.refundCap(), isNull);
    });

    test('a custom refund must be above zero and within the cap', () {
      final base = const ReturnDraft(
        order: kTwoSellerOrder,
        refundAmountType: RefundAmountType.custom,
      ).toggle(tShirt);
      Set<ReturnFormError> errors(String amount) => base
          .copyWith(customAmount: amount)
          .validate(kSampleReturnConfig, refundCap: 86);
      expect(errors(''), contains(ReturnFormError.customAmount));
      expect(errors('0'), contains(ReturnFormError.customAmount));
      expect(errors('abc'), contains(ReturnFormError.customAmount));
      expect(errors('86.01'), contains(ReturnFormError.customAmountOverCap));
      expect(
        errors('86'),
        isNot(contains(ReturnFormError.customAmountOverCap)),
      );
      expect(errors('25,5'), isNot(contains(ReturnFormError.customAmount)));
      // Arabic-Indic digits and separator.
      expect(base.copyWith(customAmount: '٢٥٫٥').customAmountValue, 25.5);
    });
  });

  group('validation', () {
    test('an empty form lists what is missing', () {
      const draft = ReturnDraft(order: kTwoSellerOrder);
      expect(draft.validate(kSampleReturnConfig), {
        ReturnFormError.items,
        ReturnFormError.reason,
        ReturnFormError.packageOpened,
        ReturnFormError.comment,
      });
    });

    test('a reason is optional when the store has reasons off', () {
      const draft = ReturnDraft(order: kTwoSellerOrder);
      expect(
        draft.validate(const ReturnConfig()),
        isNot(contains(ReturnFormError.reason)),
      );
    });

    test('a written reason must be there and short enough', () {
      final draft = const ReturnDraft(
        order: kTwoSellerOrder,
        otherReasonSelected: true,
      );
      expect(
        draft.validate(kSampleReturnConfig),
        contains(ReturnFormError.reason),
      );
      expect(
        draft.copyWith(otherReason: 'x' * 256).validate(kSampleReturnConfig),
        contains(ReturnFormError.otherReasonTooLong),
      );
      expect(
        draft
            .copyWith(otherReason: 'Wrong colour')
            .validate(kSampleReturnConfig),
        isNot(contains(ReturnFormError.reason)),
      );
    });

    test('a complete draft can go', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder)
          .toggle(tShirt)
          .copyWith(reasonId: 1, packageOpened: false, comment: 'Too small');
      expect(draft.validate(kSampleReturnConfig), isEmpty);
    });

    test('long texts are refused before the server does', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder)
          .toggle(tShirt)
          .copyWith(
            reasonId: 1,
            packageOpened: true,
            comment: 'x' * 5001,
            trackingCode: 't' * 256,
          );
      expect(draft.validate(kSampleReturnConfig), {
        ReturnFormError.commentTooLong,
        ReturnFormError.trackingTooLong,
      });
    });
  });

  group('HmCreateReturnInput', () {
    test('a full refund of part of a line with a listed reason', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder)
          .toggle(tShirt)
          .setQuantity(tShirt, 1, kSampleReturnConfig)
          .copyWith(
            reasonId: 1,
            packageOpened: true,
            comment: '  Size S is too small.  ',
            trackingCode: ' ',
          );
      expect(draft.toInput(), {
        'order_number': '000000150',
        'items': [
          {'order_item_id': 501, 'quantity': 1.0},
        ],
        'type': 'REFUND',
        'reason_id': 1,
        'package_opened': true,
        'comment': 'Size S is too small.',
        'refund_amount_type': 'FULL',
      });
    });

    test('a custom refund with a written reason and tracking', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder)
          .toggle(tShirt)
          .copyWith(
            reasonId: 2,
            otherReasonSelected: true,
            otherReason: ' Wrong colour ',
            packageOpened: false,
            refundAmountType: RefundAmountType.custom,
            customAmount: '25.50',
            comment: 'Not the green in the photo',
            trackingCode: ' ARX-1182 ',
          );
      expect(draft.toInput(), {
        'order_number': '000000150',
        'items': [
          {'order_item_id': 501, 'quantity': 2.0},
        ],
        'type': 'REFUND',
        'other_reason': 'Wrong colour',
        'package_opened': false,
        'comment': 'Not the green in the photo',
        'refund_amount_type': 'CUSTOM',
        'refund_custom_amount': 25.5,
        'tracking_code': 'ARX-1182',
      });
    });

    test('an exchange sends no refund fields', () {
      final draft = const ReturnDraft(order: kTwoSellerOrder)
          .toggle(sofa)
          .copyWith(
            type: ReturnType.replace,
            reasonId: 3,
            packageOpened: true,
            refundAmountType: RefundAmountType.custom,
            customAmount: '10',
            comment: 'Wrong colour',
          );
      final input = draft.toInput();
      expect(input['type'], 'REPLACE');
      expect(input['items'], [
        {'order_item_id': 503, 'quantity': 1.0},
      ]);
      expect(input.containsKey('refund_amount_type'), isFalse);
      expect(input.containsKey('refund_custom_amount'), isFalse);
      // An exchange ignores the refund fields in validation too.
      expect(draft.validate(kSampleReturnConfig), isEmpty);
    });

    test('lines keep the order’s line order', () {
      const order = ReturnableOrder(
        number: '1',
        createdAt: '',
        statusLabel: '',
        items: [
          ReturnableItem(orderItemId: 9, name: 'a', qtyReturnable: 1),
          ReturnableItem(orderItemId: 3, name: 'b', qtyReturnable: 1),
        ],
      );
      final draft = const ReturnDraft(
        order: order,
      ).toggle(order.items[1]).toggle(order.items[0]);
      expect(
        (draft.toInput()['items'] as List).map((i) => i['order_item_id']),
        [9, 3],
      );
    });

    test('photos go as attachments, only when there are some', () {
      final photo = ReturnPhoto(
        name: 'photo-1-1.png',
        mimeType: 'image/png',
        bytes: kGreenPhoto,
      );
      final draft = const ReturnDraft(order: kTwoSellerOrder)
          .toggle(tShirt)
          .copyWith(reasonId: 1, packageOpened: true, comment: 'Torn');
      expect(draft.toInput().containsKey('attachments'), isFalse);
      expect(draft.copyWith(photos: [photo]).toInput()['attachments'], [
        {
          'name': 'photo-1-1.png',
          'mime_type': 'image/png',
          'content_base64': base64Encode(kGreenPhoto),
        },
      ]);
    });
  });
}
