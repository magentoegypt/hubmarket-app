import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/features/catalog/domain/product.dart';
import 'package:hubmarket_app/features/catalog/domain/product_detail.dart';

import '../../../support/fakes.dart';

/// A review with a Magento `average_rating` (0–100).
ProductReview _review(int averageRating) => ProductReview(
  nickname: 'Shopper',
  summary: '',
  text: '',
  averageRating: averageRating,
  date: '2026-09-01 10:00:00',
);

/// `[stars, count, percent]` per bar, for compact assertions.
List<List<int>> _bars(List<RatingBar> bars) => [
  for (final b in bars) [b.stars, b.count, b.percent],
];

void main() {
  group('ProductDetail', () {
    test('isConfigurable reflects options', () {
      expect(kSampleDetail.isConfigurable, isTrue);
    });

    test('variantFor returns null until a full selection is made', () {
      expect(kSampleDetail.variantFor({}), isNull);
    });

    test('variantFor matches the selected attribute combination', () {
      final v50 = kSampleDetail.variantFor({'size': 1});
      final v100 = kSampleDetail.variantFor({'size': 2});
      expect(v50?.sku, 'COCO-50');
      expect(v50?.price?.amount, 199);
      expect(v100?.sku, 'COCO-100');
      expect(v100?.price?.amount, 299);
    });

    test('no reviews -> hasReviews is false and no histogram', () {
      expect(kSampleDetail.hasReviews, isFalse);
      expect(kSampleDetail.ratingHistogram, isEmpty);
    });

    group('what is left ("Only 3 left in size M")', () {
      const sizes = ConfigurableOption(
        attributeCode: 'size',
        label: 'Size',
        values: [
          SwatchValue(valueIndex: 1, label: 'S'),
          SwatchValue(valueIndex: 2, label: 'M'),
        ],
      );
      const colours = ConfigurableOption(
        attributeCode: 'color',
        label: 'Colour',
        values: [SwatchValue(valueIndex: 9, label: 'Beige floral')],
      );
      const dress = ProductDetail(
        sku: 'DRESS',
        name: 'Dress',
        urlKey: 'dress',
        options: [colours, sizes],
        variants: [
          ProductVariant(
            sku: 'DRESS-S',
            attributes: {'color': 9, 'size': 1},
            onlyLeft: 12,
          ),
          ProductVariant(sku: 'DRESS-M', attributes: {'color': 9, 'size': 2}),
        ],
      );

      test("a variant's count, once the whole choice is made", () {
        expect(dress.onlyLeftFor({'color': 9, 'size': 1}), 12);
        // Not reported for M; nothing chosen yet; half a choice.
        expect(dress.onlyLeftFor({'color': 9, 'size': 2}), isNull);
        expect(dress.onlyLeftFor({}), isNull);
        expect(dress.onlyLeftFor({'color': 9}), isNull);
      });

      test('a product without options has its own count', () {
        const simple = ProductDetail(
          sku: 'S',
          name: 'S',
          urlKey: 's',
          onlyLeft: 2,
        );
        expect(simple.onlyLeftFor({}), 2);
        expect(simple.stockOptionLabel({}), isNull);
      });

      test('names the chosen value of the last option, as "size M"', () {
        expect(dress.stockOptionLabel({'color': 9, 'size': 2}), 'size M');
        expect(dress.stockOptionLabel({'color': 9}), isNull);
      });
    });

    group('primaryCategory (where "See all" goes)', () {
      ProductDetail filed(List<ProductCategoryRef> categories) => ProductDetail(
        sku: 'S',
        name: 'S',
        urlKey: 's',
        categories: categories,
      );

      test('the deepest category in the menu', () {
        final detail = filed(const [
          ProductCategoryRef(uid: 'a', name: 'Clothes', level: 2),
          ProductCategoryRef(uid: 'b', name: 'Dresses', level: 3),
          ProductCategoryRef(uid: 'c', name: 'Hidden', level: 4, inMenu: false),
        ]);
        expect(detail.primaryCategory?.uid, 'b');
      });

      test('a category outside the menu only when nothing else is filed', () {
        expect(
          filed(const [
            ProductCategoryRef(uid: 'c', name: 'Hidden', level: 4, inMenu: false),
          ]).primaryCategory?.uid,
          'c',
        );
        expect(filed(const []).primaryCategory, isNull);
      });
    });
  });

  group('RatingBar.histogramOf (client-side rating histogram)', () {
    test('buckets by rounded stars, 5★ first, with percentages', () {
      // 100 -> 5★, 90 -> 4.5 rounds to 5★, 80 -> 4★, 60 -> 3★.
      final bars = RatingBar.histogramOf([
        _review(100),
        _review(90),
        _review(80),
        _review(60),
      ]);
      expect(_bars(bars), [
        [5, 2, 50],
        [4, 1, 25],
        [3, 1, 25],
        [2, 0, 0],
        [1, 0, 0],
      ]);
    });

    test('uses the same stars as the review card', () {
      final review = _review(70); // 3.5 -> 4 stars on the card
      final bars = RatingBar.histogramOf([review]);
      expect(bars.firstWhere((b) => b.count == 1).stars, review.stars);
    });

    test('percentages are rounded shares of the rated reviews', () {
      final bars = RatingBar.histogramOf([
        _review(100),
        _review(100),
        _review(20),
      ]);
      expect(_bars(bars), [
        [5, 2, 67],
        [4, 0, 0],
        [3, 0, 0],
        [2, 0, 0],
        [1, 1, 33],
      ]);
    });

    test('reviews without a rating are left out, never invented', () {
      final bars = RatingBar.histogramOf([_review(0), _review(100)]);
      expect(_bars(bars).first, [5, 1, 100]);
      expect(bars.fold<int>(0, (sum, b) => sum + b.count), 1);
    });

    test('no rated reviews -> empty histogram', () {
      expect(RatingBar.histogramOf(const []), isEmpty);
      expect(RatingBar.histogramOf([_review(0)]), isEmpty);
    });

    test('no bars when the PDP holds only some of the reviews', () {
      // 21+ reviews: the PDP loads 20, which say nothing about the rest.
      final detail = ProductDetail(
        sku: 'S',
        name: 'N',
        urlKey: 'u',
        reviewCount: 3,
        reviews: [_review(100), _review(40)],
      );
      expect(detail.ratingHistogram, isEmpty);
      expect(RatingBar.exactHistogram([_review(100)], 1), hasLength(5));
      expect(RatingBar.exactHistogram(const [], 0), isEmpty);
    });

    test('the PDP derives its histogram from its loaded reviews', () {
      final detail = ProductDetail(
        sku: 'S',
        name: 'N',
        urlKey: 'u',
        reviewCount: 2,
        reviews: [_review(100), _review(40)],
      );
      expect(_bars(detail.ratingHistogram), [
        [5, 1, 50],
        [4, 0, 0],
        [3, 0, 0],
        [2, 1, 50],
        [1, 0, 0],
      ]);
    });
  });
}
