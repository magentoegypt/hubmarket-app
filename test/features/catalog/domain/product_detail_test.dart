import 'package:flutter_test/flutter_test.dart';
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
