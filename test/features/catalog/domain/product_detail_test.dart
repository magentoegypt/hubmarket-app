import 'package:flutter_test/flutter_test.dart';

import '../../../support/fakes.dart';

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

    test('no reviews -> hasReviews is false', () {
      expect(kSampleDetail.hasReviews, isFalse);
    });
  });
}
