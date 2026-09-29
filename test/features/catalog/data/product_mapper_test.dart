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

/// A `related_products` / `upsell_products` entry as the PDP query selects it.
Map<String, dynamic> _linked(String sku, {String? urlKey}) => {
  'sku': sku,
  'name': 'Product $sku',
  'url_key': urlKey ?? 'product-${sku.toLowerCase()}',
  'stock_status': 'IN_STOCK',
  'image': {'url': 'http://hub-market.magento2.click/media/$sku.jpg'},
  'price_range': {
    'minimum_price': {
      'regular_price': {'value': 100, 'currency': 'AED'},
      'final_price': {'value': 80, 'currency': 'AED'},
    },
  },
};

List<String> _skus(List<Product> products) =>
    products.map((p) => p.sku).toList();

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

  group('"You may also like" from related_products + upsell_products', () {
    test('related first, then upsell, de-duplicated by sku', () {
      final json = {
        'sku': 'MH09',
        'related_products': [_linked('A'), _linked('B')],
        'upsell_products': [_linked('B'), _linked('C')],
      };
      expect(_skus(alsoLikeFromJson(json)), ['A', 'B', 'C']);
    });

    test('never recommends the product itself (the live catalogue does)', () {
      final json = {
        'sku': 'MH09',
        'related_products': [_linked('MH09'), _linked('A')],
        'upsell_products': [_linked('MH09')],
      };
      expect(_skus(alsoLikeFromJson(json)), ['A']);
    });

    test('caps the merged list at 8', () {
      final json = {
        'sku': 'SELF',
        'related_products': [for (var i = 0; i < 6; i++) _linked('R$i')],
        'upsell_products': [for (var i = 0; i < 6; i++) _linked('U$i')],
      };
      expect(_skus(alsoLikeFromJson(json)), [
        'R0',
        'R1',
        'R2',
        'R3',
        'R4',
        'R5',
        'U0',
        'U1',
      ]);
    });

    test('skips null entries and entries that cannot open a PDP', () {
      final json = {
        'sku': 'SELF',
        'related_products': [
          null,
          _linked(''),
          _linked('NOKEY', urlKey: ''),
          _linked('D'),
        ],
      };
      expect(_skus(alsoLikeFromJson(json)), ['D']);
    });

    test('nothing linked => empty, so the rail hides', () {
      expect(alsoLikeFromJson({'sku': 'SELF'}), isEmpty);
      expect(
        alsoLikeFromJson({
          'sku': 'SELF',
          'related_products': <dynamic>[],
          'upsell_products': null,
        }),
        isEmpty,
      );
    });

    test('cards use the listing mapping (https image, prices, NEW)', () {
      final card = alsoLikeFromJson({
        'sku': 'SELF',
        'related_products': [
          {..._linked('A'), 'new_from_date': '2026-09-20 00:00:00'},
        ],
      }, now: _today).single;
      expect(card.urlKey, 'product-a');
      expect(card.imageUrl, 'https://hub-market.magento2.click/media/A.jpg');
      expect(card.discountPercent, 20);
      expect(card.badge, ProductBadge.isNew);
    });

    test('the PDP detail carries the merged list', () {
      final detail = productDetailFromJson({
        ..._json(),
        'related_products': [_linked('A')],
        'upsell_products': [_linked('B'), _linked('A')],
      });
      expect(_skus(detail.alsoLike), ['A', 'B']);
    });
  });

  group('rating histogram from the loaded reviews', () {
    test('built from reviews.items, with no server histogram field', () {
      final detail = productDetailFromJson({
        ..._json(),
        'rating_summary': 93,
        'review_count': 3,
        'reviews': {
          'items': [
            {'nickname': 'A', 'average_rating': 100},
            {'nickname': 'B', 'average_rating': 100},
            {'nickname': 'C', 'average_rating': 80},
          ],
        },
      });
      expect(detail.reviews, hasLength(3));
      expect(
        [for (final b in detail.ratingHistogram) (b.stars, b.count, b.percent)],
        [(5, 2, 67), (4, 1, 33), (3, 0, 0), (2, 0, 0), (1, 0, 0)],
      );
    });

    test('no reviews => no bars', () {
      expect(productDetailFromJson(_json()).ratingHistogram, isEmpty);
    });

    test('rating_summary is a Float in the schema — fractional is tolerated', () {
      final detail = productDetailFromJson({
        ..._json(),
        'rating_summary': 93.3,
        'review_count': 3,
      });
      expect(detail.ratingSummary, 93);
    });
  });

  group('PDP "More Information" attributes', () {
    Map<String, dynamic> selected(String code, List<String> labels) => {
      'code': code,
      'selected_options': [
        for (final label in labels) {'label': label, 'value': '1'},
      ],
    };

    test("Hub Market's mgs_brand is the brand", () {
      final detail = productDetailFromJson({
        ..._json(),
        'custom_attributesV2': {
          'items': [
            selected('color', ['Black']),
            selected('mgs_brand', ['Samsung']),
          ],
        },
      });
      expect(detail.brand, 'Samsung');
      expect(
        [for (final a in detail.attributes) (a.code, a.value, a.isBrand)],
        [('color', 'Black', false), ('mgs_brand', 'Samsung', true)],
      );
    });

    test('a multiselect lists every label, entity-decoded', () {
      final detail = productDetailFromJson({
        ..._json(),
        'custom_attributesV2': {
          'items': [
            selected('material', ['Nylon', 'CoolTech&trade;', 'Wool']),
            selected('climate', ['Spring', ' ']),
            {'code': 'dimensions', 'value': ' high width '},
            {'code': 'pattern', 'value': ' '},
          ],
        },
      });
      expect(detail.brand, isNull);
      expect(
        [for (final a in detail.attributes) (a.code, a.value)],
        [
          ('material', 'Nylon, CoolTech™, Wool'),
          ('climate', 'Spring'),
          ('dimensions', 'high width'),
        ],
      );
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

  group('search hit categories (items.categories)', () {
    // A Hub Market bag as the search query returns it (2026-09-29): the
    // top-level "Bags" is out of the menu; include_in_menu is an Int.
    Map<String, dynamic> category(
      String uid,
      String name,
      int level,
      Object? inMenu,
    ) => {
      'uid': uid,
      'name': name,
      'level': level,
      'include_in_menu': inMenu,
    };

    test('parses uid, name, level and the Int menu flag', () {
      final product = productFromJson(
        _json(
          extra: {
            'categories': [
              category('MTI5', 'Bags', 2, 0),
              category('MTMw', "Women's Bags", 3, 1),
              category('MTMy', 'Shoulder Bag', 4, 1),
            ],
          },
        ),
      );

      expect(
        [for (final c in product.categories) (c.uid, c.name, c.level, c.inMenu)],
        [
          ('MTI5', 'Bags', 2, false),
          ('MTMw', "Women's Bags", 3, true),
          ('MTMy', 'Shoulder Bag', 4, true),
        ],
      );
      expect(product.primaryCategory?.name, 'Shoulder Bag');
    });

    test('the "in …" category is the deepest shown in the menu', () {
      final product = productFromJson(
        _json(
          extra: {
            'categories': [
              category('NzQ=', 'Furniture', 2, 1),
              category('Mzk=', 'Clearance', 4, 0),
              category('NzU=', 'Home Furniture', 3, 1),
            ],
          },
        ),
      );
      expect(product.primaryCategory?.name, 'Home Furniture');
    });

    test('with none in the menu, the deepest of any', () {
      final product = productFromJson(
        _json(
          extra: {
            'categories': [
              category('MTY4', 'All', 2, 0),
              category('MzU=', 'Performance Fabrics', 3, 0),
            ],
          },
        ),
      );
      expect(product.primaryCategory?.name, 'Performance Fabrics');
    });

    test('drops entries with no uid or name; listings carry none', () {
      final product = productFromJson(
        _json(
          extra: {
            'categories': [
              {'uid': '', 'name': 'Nameless uid'},
              {'uid': 'NzQ=', 'name': '  '},
              null,
              category('NzU=', 'Home Furniture', 3, null),
            ],
          },
        ),
      );
      expect(product.categories.map((c) => c.name), ['Home Furniture']);
      // An absent flag counts as shown, as in the category tree.
      expect(product.categories.single.inMenu, isTrue);

      final listing = productFromJson(_json());
      expect(listing.categories, isEmpty);
      expect(listing.primaryCategory, isNull);
    });
  });
}
