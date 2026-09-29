import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../data/home_sections_provider.dart';
import '../../domain/home_config.dart';

/// Full "Customer Reviews" list — reached from the home "Why Shoppers Trust
/// Hub Market" rail's See More. Shows every review the `homeReviews` feed carries
/// (the home rail shows only a 3-item slice), led by an average-rating summary.
/// Degrades to an empty state when the feed returns nothing.
class AllReviewsScreen extends ConsumerWidget {
  const AllReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return HubScaffold(
      currentTab: AppTab.home,
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(l10n.reviewsScreenTitle),
      ),
      body: AsyncValueView<List<Testimonial>>(
        value: ref.watch(allReviewsProvider),
        onRetry: () => ref.invalidate(allReviewsProvider),
        loading: () => const _ReviewsSkeleton(),
        data: (reviews) => reviews.isEmpty
            ? const _ReviewsEmpty()
            : _ReviewsList(reviews: reviews),
      ),
    );
  }
}

class _ReviewsList extends StatelessWidget {
  const _ReviewsList({required this.reviews});
  final List<Testimonial> reviews;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: reviews.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      // Row 0 is the average-rating summary; the rest are the reviews.
      itemBuilder: (context, i) => i == 0
          ? _ReviewsSummary(reviews: reviews)
          : _ReviewCard(review: reviews[i - 1]),
    );
  }
}

/// Average-rating summary card at the top of the list (big average · stars ·
/// count), computed from the loaded reviews — no fabricated numbers.
class _ReviewsSummary extends StatelessWidget {
  const _ReviewsSummary({required this.reviews});
  final List<Testimonial> reviews;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final avg =
        reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            avg.toStringAsFixed(1),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              color: AppColors.brandPrimary,
              height: 1,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _ReviewStars(rating: avg.round()),
              const SizedBox(height: 6),
              Text(
                l10n.reviewsCount(reviews.length),
                style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One full-width review: avatar initials · name · stars, then the quote and
/// the product it's about.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Testimonial review;

  String get _initials {
    final parts = review.author.trim().split(RegExp(r'\s+'));
    final letters = parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letters.isEmpty ? '★' : letters;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceTint,
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: AppColors.brandPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (review.author.isNotEmpty) ...[
                      Text(
                        review.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.inkHeading,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    _ReviewStars(rating: review.rating),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '“${review.quote}”',
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          if (review.product.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.product.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.inkFaint,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A gold 0–5 star row (filled + outlined to five); symmetric, so it reads the
/// same under LTR and RTL.
class _ReviewStars extends StatelessWidget {
  const _ReviewStars({required this.rating});
  final int rating;

  @override
  Widget build(BuildContext context) {
    final full = rating.clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < full ? Icons.star : Icons.star_border,
            size: 18,
            color: AppColors.accentGold,
          ),
      ],
    );
  }
}

class _ReviewsEmpty extends StatelessWidget {
  const _ReviewsEmpty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.reviews_outlined,
            size: 48,
            color: AppColors.inkFaint,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.reviewsEmptyTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.inkHeading,
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading placeholder: a summary block + a few review-card shimmers.
class _ReviewsSkeleton extends StatelessWidget {
  const _ReviewsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => SkeletonBox(
          width: double.infinity,
          height: i == 0 ? 84 : 140,
          borderRadius: i == 0 ? 16 : 14,
        ),
      ),
    );
  }
}
