import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/domain/aggregation.dart';
import 'package:hubmarket_app/features/catalog/domain/category.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/search_facets.dart';
import 'package:hubmarket_app/features/catalog/domain/search_highlight.dart';

Aggregation _categoryFacet(List<(String, String, int)> options) => Aggregation(
  attributeCode: kCategoryAggregationCode,
  label: 'Category',
  options: [
    for (final (label, value, count) in options)
      AggregationOption(label: label, value: value, count: count),
  ],
);

Product _hit(List<ProductCategoryRef> categories) =>
    Product(sku: 'sku', name: 'name', urlKey: 'key', categories: categories);

List<String> _names(List<SearchCategory> categories) =>
    categories.map((c) => c.name).toList();

void main() {
  group('searchCategoriesFrom', () {
    // "bag" on Hub Market (2026-09-29): the top-level "Bags" is out of the
    // menu, its children are in it.
    final bagHits = [
      _hit(const [
        ProductCategoryRef(uid: 'MTI5', name: 'Bags', level: 2, inMenu: false),
        ProductCategoryRef(uid: 'MTMw', name: "Women's Bags", level: 3),
        ProductCategoryRef(uid: 'MTMx', name: 'Handbag', level: 4),
        ProductCategoryRef(uid: 'MTM2', name: "Men's Bags", level: 3),
      ]),
    ];

    test('keeps categories a hit files in the menu, by match count', () {
      final result = searchCategoriesFrom(
        aggregations: [
          _categoryFacet([
            ('Bags', 'MTI5', 14),
            ("Women's Bags", 'MTMw', 12),
            ("Men's Bags", 'MTM2', 10),
            ('Handbag', 'MTMx', 7),
          ]),
        ],
        products: bagHits,
      );

      expect(_names(result), ["Women's Bags", "Men's Bags", 'Handbag']);
      expect(result.first.count, 12);
      expect(result.first.level, 3);
    });

    test('falls back to the menu tree; anything unknown is dropped', () {
      const tree = [
        Category(
          uid: 'Mw==',
          name: 'Gear',
          urlKey: 'gear',
          children: [
            Category(uid: 'NQ==', name: 'Fitness', urlKey: 'fitness'),
            Category(
              uid: 'OA==',
              name: 'Hidden',
              urlKey: 'hidden',
              includeInMenu: false,
            ),
          ],
        ),
      ];
      final result = searchCategoriesFrom(
        aggregations: [
          _categoryFacet([
            ('Gear', 'Mw==', 7),
            ('Fitness', 'NQ==', 2),
            ('Hidden', 'OA==', 2),
            ('All', 'MTY4', 17),
          ]),
        ],
        products: const [],
        tree: tree,
      );

      expect(_names(result), ['Gear', 'Fitness']);
      expect(result.map((c) => c.level), [2, 3]);
    });

    test('ties go to the deeper category, then to the aggregation order', () {
      final result = searchCategoriesFrom(
        aggregations: [
          _categoryFacet([
            ('Furniture', 'NzQ=', 1),
            ('Home Furniture', 'NzU=', 1),
            ('Office Furniture', 'NzY=', 1),
          ]),
        ],
        products: [
          _hit(const [
            ProductCategoryRef(uid: 'NzQ=', name: 'Furniture', level: 2),
            ProductCategoryRef(uid: 'NzU=', name: 'Home Furniture', level: 3),
            ProductCategoryRef(uid: 'NzY=', name: 'Office Furniture', level: 3),
          ]),
        ],
      );

      expect(_names(result), [
        'Home Furniture',
        'Office Furniture',
        'Furniture',
      ]);
    });

    test('leaves out the scope, empty options and a missing facet', () {
      final hits = [
        _hit(const [
          ProductCategoryRef(uid: 'NzQ=', name: 'Furniture', level: 2),
          ProductCategoryRef(uid: 'NzU=', name: 'Home Furniture', level: 3),
        ]),
      ];
      final result = searchCategoriesFrom(
        aggregations: [
          _categoryFacet([
            ('Furniture', 'NzQ=', 3),
            ('Home Furniture', 'NzU=', 0),
          ]),
        ],
        products: hits,
        excludeUid: 'NzQ=',
      );
      expect(result, isEmpty);

      expect(
        searchCategoriesFrom(
          aggregations: const [
            Aggregation(attributeCode: 'price', label: 'Price', options: []),
          ],
          products: hits,
        ),
        isEmpty,
      );
    });
  });

  group('searchMatchSlices', () {
    test('marks each word of the query, case-insensitively', () {
      expect(searchMatchSlices('Corner Sofa Bed', 'sofa'), [
        (start: 7, end: 11),
      ]);
      expect(searchMatchSlices('Corner Sofa Bed', 'BED sofa'), [
        (start: 7, end: 11),
        (start: 12, end: 15),
      ]);
    });

    test('merges overlapping words and finds repeats', () {
      expect(searchMatchSlices('sofa bed sofa', 'sofa so'), [
        (start: 0, end: 4),
        (start: 9, end: 13),
      ]);
    });

    test('Arabic matches the same way', () {
      expect(searchMatchSlices('كنبة سرير ركنه', 'كنبة'), [(start: 0, end: 4)]);
    });

    test('nothing to mark when nothing matches literally', () {
      expect(searchMatchSlices('Corner Sofa Bed', 'couch'), isEmpty);
      expect(searchMatchSlices('Corner Sofa Bed', '   '), isEmpty);
      expect(searchMatchSlices('', 'sofa'), isEmpty);
    });
  });
}
