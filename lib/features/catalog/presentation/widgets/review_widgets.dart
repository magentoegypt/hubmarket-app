import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/product_detail.dart';

/// Shared review UI for the product page, the Reviews screen (Figma 15) and
/// My product reviews (Figma 20f).

/// Five stars, the first [stars] filled: Figma "icon/star" in a [size] box (11,
/// 12 or 14 px), 2 px apart, `rating-star` lit and `rating-empty` unlit. The
/// frame's star fills 6/7 of its box; the Material glyph only 5/7 of its own,
/// so it is drawn a fifth larger than the box and the box keeps the pitch.
class ReviewStars extends StatelessWidget {
  const ReviewStars({super.key, required this.stars, this.size = 14});

  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++) ...[
        if (i > 1) const SizedBox(width: 2),
        SizedBox(
          width: size,
          height: size,
          child: OverflowBox(
            maxWidth: size * 1.2,
            maxHeight: size * 1.2,
            child: Icon(
              Icons.star_rounded,
              size: size * 1.2,
              color: i <= stars ? AppColors.ratingStar : AppColors.ratingEmpty,
            ),
          ),
        ),
      ],
    ],
  );
}

/// A review's date, e.g. "12 Sep 2026". Magento stores `created_at` in UTC.
String reviewDate(String raw, String locale) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = DateTime.tryParse(
    value.contains('T') || value.endsWith('Z')
        ? value
        : '${value.replaceFirst(' ', 'T')}Z',
  );
  if (parsed == null) return value;
  try {
    return DateFormat('d MMM yyyy', locale).format(parsed.toLocal());
  } catch (_) {
    return DateFormat('d MMM yyyy').format(parsed.toLocal());
  }
}

/// The average, the stars, the count and — when [histogram] is known exactly
/// — the per-star bars.
class ReviewsSummaryCard extends StatelessWidget {
  const ReviewsSummaryCard({
    super.key,
    required this.ratingSummary,
    required this.reviewCount,
    required this.histogram,
  });

  /// 0–100 (`rating_summary`).
  final int ratingSummary;
  final int reviewCount;

  /// Empty when the distribution can't be counted exactly; see
  /// [RatingBar.exactHistogram].
  final List<RatingBar> histogram;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final average = ratingSummary / 20;
    final overview = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          average.toStringAsFixed(1),
          style: TextStyle(
            fontFamily: AppTheme.displayFont,
            fontFamilyFallback: const [AppTheme.arabicFont],
            fontSize: 38,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: context.scaffoldHeading,
          ),
        ),
        const SizedBox(height: 4),
        ReviewStars(stars: average.round(), size: 16),
        const SizedBox(height: 4),
        Text(
          l10n.reviewsCount(reviewCount),
          style: TextStyle(fontSize: 12.5, color: context.scaffoldMuted),
        ),
      ],
    );
    final byStar = {for (final b in histogram) b.stars: b};
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: context.isDarkMode ? Colors.white10 : AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: histogram.isEmpty
          ? Center(child: overview)
          : Row(
              children: [
                SizedBox(width: 104, child: overview),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (var star = 5; star >= 1; star--)
                        _Bar(
                          stars: star,
                          count: byStar[star]?.count ?? 0,
                          fraction: (byStar[star]?.percent ?? 0) / 100,
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.stars, required this.count, required this.fraction});

  final int stars;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12, color: context.scaffoldMuted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 12, child: Text('$stars', style: muted)),
          const Icon(Icons.star_rounded, size: 14, color: AppColors.accentGold),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                backgroundColor: context.isDarkMode
                    ? Colors.white12
                    : AppColors.borderDefault,
                valueColor: const AlwaysStoppedAnimation(AppColors.accentGold),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text('$count', textAlign: TextAlign.end, style: muted),
          ),
        ],
      ),
    );
  }
}

/// One review: initials avatar, name, stars and date, then the title and
/// text. Magento's core review has no photos, helpful votes, "verified
/// purchase" flag, variant or store reply, so none is shown.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final date = reviewDate(review.date, locale);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFFFF1E6),
                child: Text(
                  reviewerInitials(review.nickname),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.accentStrong,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.nickname,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.scaffoldHeading,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        ReviewStars(stars: review.stars),
                        if (date.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            date,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.scaffoldMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.summary.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.summary.trim(),
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: context.scaffoldHeading,
              ),
            ),
          ],
          if (review.text.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              review.text.trim(),
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: context.scaffoldHeading,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Up to two initials from a reviewer's nickname; `?` when it has none.
String reviewerInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final letters = [
    parts.first.characters.first,
    if (parts.length > 1) parts.last.characters.first,
  ];
  return letters.join().toUpperCase();
}
