import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/data/product_mapper.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';

/// Fixed "today" for every date-window assertion (mid-afternoon, local time).
final _today = DateTime(2026, 9, 29, 15, 30);

Map<String, dynamic> _json({
  Object? newFrom,
  Object? newTo,
  num? regular,
  num? finalPrice,
  Map<String, dynamic> extra = const {},
}) => {
  'sku': 'SKU1',
  'name': 'Test Product',
  'url_key': 'test-product',
  'stock_status': 'IN_STOCK',
  if (newFrom != null) 'new_from_date': newFrom,
  if (newTo != null) 'new_to_date': newTo,
  if (regular != null || finalPrice != null)
    'price_range': {
      'minimum_price': {
        'regular_price': {'value': regular, 'currency': 'AED'},
        'final_price': {'value': finalPrice, 'currency': 'AED'},
      },
    },
  ...extra,
};

ProductBadge _badge(Map<String, dynamic> json) =>
    productFromJson(json, now: _today).badge;

void main() {
  group('NEW badge from new_from_date / new_to_date', () {
    test('no window => no badge', () {
      expect(_badge(_json()), ProductBadge.none);
      expect(
        _badge(_json(extra: {'new_from_date': null, 'new_to_date': null})),
        ProductBadge.none,
      );
    });

    test('open-ended window that started earlier (the live shape) => NEW', () {
      expect(
        _badge(_json(newFrom: '2026-09-10 00:00:00')),
        ProductBadge.isNew,
      );
    });

    test('both bounds are inclusive days', () {
      expect(
        _badge(_json(newFrom: '2026-09-29 00:00:00')),
        ProductBadge.isNew,
        reason: 'starts today',
      );
      expect(
        _badge(
          _json(newFrom: '2026-09-01 00:00:00', newTo: '2026-09-29 00:00:00'),
        ),
        ProductBadge.isNew,
        reason: 'ends today',
      );
    });

    test('a window that has not started yet => no badge', () {
      expect(
        _badge(_json(newFrom: '2026-09-30 00:00:00')),
        ProductBadge.none,
      );
    });

    test('an expired window => no badge', () {
      expect(
        _badge(
          _json(newFrom: '2026-08-01 00:00:00', newTo: '2026-09-28 00:00:00'),
        ),
        ProductBadge.none,
      );
    });

    test('only an end date, still ahead => NEW', () {
      expect(_badge(_json(newTo: '2026-10-05 00:00:00')), ProductBadge.isNew);
    });

    test('accepts date-only values', () {
      expect(
        _badge(_json(newFrom: '2026-09-01', newTo: '2026-10-01')),
        ProductBadge.isNew,
      );
    });

    test('unreadable, impossible or inverted dates never produce a badge', () {
      expect(_badge(_json(newFrom: 'soon')), ProductBadge.none);
      expect(_badge(_json(newFrom: '0000-00-00 00:00:00')), ProductBadge.none);
      expect(_badge(_json(newFrom: '2026-02-31 00:00:00')), ProductBadge.none);
      expect(
        _badge(_json(newFrom: '2026-09-01', newTo: 'never')),
        ProductBadge.none,
        reason: 'a set-but-unreadable end is not "open-ended"',
      );
      expect(
        _badge(_json(newFrom: '2026-10-01', newTo: '2026-09-01')),
        ProductBadge.none,
      );
    });

    test('the retired Zoonze flags no longer drive any badge', () {
      expect(
        _badge(_json(extra: {'is_new_arrival': true, 'is_bestseller': 1})),
        ProductBadge.none,
      );
    });

    test('the PDP uses the same window', () {
      final detail = productDetailFromJson(
        _json(newFrom: '2026-09-10 00:00:00'),
        now: _today,
      );
      expect(detail.badge, ProductBadge.isNew);
    });
  });

  group('discount badge from price_range (regular vs final)', () {
    test('a real markdown => rounded percent', () {
      final product = productFromJson(_json(regular: 250, finalPrice: 199));
      expect(product.isOnSale, isTrue);
      expect(product.discountPercent, 20); // 20.4% -> 20
    });

    test('equal prices => no badge', () {
      final product = productFromJson(_json(regular: 300, finalPrice: 300));
      expect(product.isOnSale, isFalse);
      expect(product.discountPercent, isNull);
    });

    test('a markdown that rounds to 0% => no "-0%" badge', () {
      final product = productFromJson(_json(regular: 400, finalPrice: 399));
      expect(product.isOnSale, isTrue);
      expect(product.discountPercent, isNull);
    });

    test('no price_range => no badge', () {
      final product = productFromJson(_json());
      expect(product.regularPrice, isNull);
      expect(product.discountPercent, isNull);
    });

    test('the PDP derives the same percent', () {
      final detail = productDetailFromJson(
        _json(regular: 200, finalPrice: 150),
      );
      expect(detail.regularPrice?.currency, 'AED');
      expect(detail.discountPercent, 25);
    });
  });
}
