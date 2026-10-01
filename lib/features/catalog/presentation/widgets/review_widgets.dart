import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../core/widgets/system_bar_clearance.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/product_detail.dart';

/// Shared review UI for the product page, the Reviews screen (Figma 15), the
/// review form (15b) and My product reviews (Figma 20f).

/// One star (Figma "icon/star") in a [size] box. The frame's star fills 6/7 of its
/// box; the Material glyph only 5/7 of its own, so it is drawn a fifth larger than
/// the box, which keeps the pitch the frame lays the stars out at.
class StarGlyph extends StatelessWidget {
  const StarGlyph({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: OverflowBox(
      maxWidth: size * 1.2,
      maxHeight: size * 1.2,
      child: Icon(Icons.star_rounded, size: size * 1.2, color: color),
    ),
  );
}

/// Five stars, the first [stars] filled: [StarGlyph]s in a [size] box (11, 12 or
/// 14 px), 2 px apart, `rating-star` lit and `rating-empty` unlit.
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
        StarGlyph(
          size: size,
          color: i <= stars ? AppColors.ratingStar : AppColors.ratingEmpty,
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

/// Figma 15 "summary": a `bg/muted` card, radius 16 — the average in Display with
/// its stars and the count on the start side, and, when [histogram] is known
/// exactly, the per-star bars (the digit, a star, a 6 px track and the count)
/// after it, 20 px apart. Without the bars the figure stands alone in the middle.
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
    final t = AppTextStyles.of(context);
    final average = ratingSummary / 20;
    final overview = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          average.toStringAsFixed(1),
          style: t.display.copyWith(color: AppColors.inkHeading),
        ),
        const SizedBox(height: 4),
        ReviewStars(stars: average.round(), size: 14),
        const SizedBox(height: 4),
        Text(
          l10n.reviewsCount(reviewCount),
          style: t.caption.copyWith(color: AppColors.inkMuted),
        ),
      ],
    );
    final byStar = {for (final b in histogram) b.stars: b};
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: histogram.isEmpty
          ? Center(child: overview)
          : Row(
              children: [
                overview,
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      for (var star = 5; star >= 1; star--) ...[
                        if (star < 5) const SizedBox(height: 6),
                        _Bar(
                          stars: star,
                          count: byStar[star]?.count ?? 0,
                          fraction: (byStar[star]?.percent ?? 0) / 100,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// One row of the bars: "5", a 12 px star, the 6 px track with its fill, and the
/// count — 8 px apart, 16 px high.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.stars,
    required this.count,
    required this.fraction,
  });

  final int stars;
  final int count;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return SizedBox(
      height: 16,
      child: Row(
        children: [
          SizedBox(
            width: 10,
            child: Text(
              '$stars',
              style: t.captionStrong.copyWith(color: AppColors.inkHeading),
            ),
          ),
          const SizedBox(width: 8),
          const StarGlyph(size: 12, color: AppColors.ratingStar),
          const SizedBox(width: 8),
          Expanded(
            // Rounded at both ends, the fill too: a lone review is a dot.
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: AppColors.borderSubtle,
              valueColor: const AlwaysStoppedAnimation(AppColors.ratingStar),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 22,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: t.caption.copyWith(color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// One review (Figma 15 "review"): a 36 px initials avatar on `accent-subtle`, the
/// name in Body Strong over the 12 px stars and the date, then the title and
/// the text, a hairline under it, 14 px above and below, 8 px between the parts.
/// Magento's core review has no photos, helpful votes, "verified purchase"
/// flag, variant or store reply, so none is shown.
class ReviewCard extends StatelessWidget {
  const ReviewCard({super.key, required this.review});

  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final date = reviewDate(review.date, locale);
    final summary = review.summary.trim();
    final text = review.text.trim();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.accentSubtle,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  reviewerInitials(review.nickname),
                  style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        ReviewStars(stars: review.stars, size: 12),
                        if (date.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            date,
                            style: t.caption.copyWith(color: AppColors.inkMuted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary,
              style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
            ),
          ],
          if (text.isNotEmpty) ...[
            SizedBox(height: summary.isEmpty ? 8 : 2),
            Text(text, style: t.body.copyWith(color: AppColors.inkHeading)),
          ],
        ],
      ),
    );
  }
}

/// Up to two initials from a reviewer's nickname; `?` when it has none. An Arabic
/// name is marked by its first letter alone, as the Arabic frame does ("ن" for
/// "نور أ."): its letters join, and two of them side by side read as a word.
String reviewerInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  if (RegExp(r'[؀-ۿ]').hasMatch(first)) return first;
  final letters = [
    first,
    if (parts.length > 1) parts.last.characters.first,
  ];
  return letters.join().toUpperCase();
}

/// The "App bar" of Figma 15 and 15b: [HubTopBar]'s 56 px row with the frame's 1 px
/// `border/subtle` rule along its bottom edge — drawn over the row's last pixel,
/// as the frame's inside border is, so the bar stays 56 px high.
class RuledTopBar extends StatelessWidget implements PreferredSizeWidget {
  const RuledTopBar({
    super.key,
    required this.title,
    this.leading,
    this.showBack,
  });

  final String title;

  /// Replaces the back button (the form's close "×").
  final Widget? leading;
  final bool? showBack;

  @override
  Size get preferredSize => const Size.fromHeight(HubTopBar.rowHeight);

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      HubTopBar(title: title, leading: leading, showBack: showBack),
      const PositionedDirectional(
        start: 0,
        end: 0,
        bottom: 0,
        child: Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
      ),
    ],
  );
}

/// The footer of Figma 15 and 15b: a white bar with a 1 px `border/subtle` rule on
/// top, 12 px above its [child] and, below, the home-indicator zone — the device's
/// own bottom inset less [indicatorGap] (the Reviews frame leaves 30 under the
/// button in its 34 px zone, the form's 28: 4 and 6). The offline banner docks
/// above it.
class ScreenFooter extends StatelessWidget {
  const ScreenFooter({super.key, required this.child, this.indicatorGap = 4});

  final Widget child;
  final double indicatorGap;

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(
      systemBarClearance(context, iosGap: indicatorGap),
      12.0,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OfflineBannerSlot(),
        Container(
          width: double.infinity,
          padding: EdgeInsetsDirectional.fromSTEB(16, 12, 16, bottom),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: child,
        ),
      ],
    );
  }
}
