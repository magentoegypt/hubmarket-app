import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

/// The review count of the product page ("3 reviews", the rating row, the
/// histogram) says one review in the singular and, in Arabic, uses the right
/// form for the number (the way `myReviewsCount` and `storeReviewCount` do).
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ar = lookupAppLocalizations(const Locale('ar'));

  test('English: one review, otherwise reviews', () {
    expect(en.reviewsCount(1), '1 review');
    expect(en.reviewsCount(0), '0 reviews');
    expect(en.reviewsCount(2), '2 reviews');
    expect(en.reviewsCount(27), '27 reviews');
    expect(en.pdpRatingReviews('4.5', 1), '4.5 · 1 review');
    expect(en.pdpRatingReviews('4.5', 3), '4.5 · 3 reviews');
  });

  test('Arabic: the form that goes with the number', () {
    expect(ar.reviewsCount(1), 'تقييم واحد');
    expect(ar.reviewsCount(2), 'تقييمان');
    expect(ar.reviewsCount(3), '3 تقييمات');
    expect(ar.reviewsCount(10), '10 تقييمات');
    expect(ar.reviewsCount(11), '11 تقييمًا');
    expect(ar.reviewsCount(99), '99 تقييمًا');
    expect(ar.reviewsCount(100), '100 تقييم');
    expect(ar.pdpRatingReviews('4.5', 1), '4.5 · تقييم واحد');
    expect(ar.pdpRatingReviews('4.5', 5), '4.5 · 5 تقييمات');
  });
}
