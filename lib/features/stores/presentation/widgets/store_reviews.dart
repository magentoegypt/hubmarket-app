import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/widgets/review_widgets.dart';
import '../../domain/store_review.dart';
import '../store_reviews_controller.dart';
import '../../../../app/theme/hub_icons.dart';

/// Figma 13's Reviews tab, as slivers of the store page: the seller's rating
/// (the header's figures: every approved review of its products), then the
/// reviews this store view shows, newest first, each with the product it is
/// about. [onRetry] reloads after a failure.
List<Widget> storeReviewsSlivers(
  BuildContext context,
  StoreReviewsState state, {
  required VoidCallback onRetry,
}) {
  final l10n = AppLocalizations.of(context);
  if (state.isLoading && state.items.isEmpty) {
    return const [
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    ];
  }
  final error = state.error;
  if (error != null && state.items.isEmpty) {
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                error is Failure
                    ? failureMessage(context, error)
                    : l10n.errorGeneric,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
            ],
          ),
        ),
      ),
    ];
  }
  final rating = state.rating;
  return [
    if (rating != null && state.reviewCount > 0)
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 4),
        sliver: SliverToBoxAdapter(
          child: ReviewsSummaryCard(
            ratingSummary: (rating * 20).round(),
            reviewCount: state.reviewCount,
            histogram: const [],
          ),
        ),
      ),
    if (state.items.isEmpty)
      SliverToBoxAdapter(
        child: EmptyState(
          icon: HubIcons.messageSquareText,
          title: l10n.storeNoReviews,
          // The seller's reviews exist, just not in this store view's language.
          body: state.reviewCount > 0 ? l10n.storeReviewsOtherLanguage : null,
        ),
      )
    else
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 16),
        sliver: SliverList.separated(
          itemCount: state.items.length,
          separatorBuilder: (context, _) =>
              Divider(height: 1, thickness: 1, color: context.hairline),
          itemBuilder: (context, i) => StoreReviewCard(review: state.items[i]),
        ),
      ),
    if (state.isLoadingMore)
      const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
  ];
}

/// One review of the seller's products: the reviewer, stars and date, the
/// title and text, and the product it is about — which opens its page while
/// the storefront lists it.
class StoreReviewCard extends StatelessWidget {
  const StoreReviewCard({super.key, required this.review});

  final StoreReview review;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final created = review.createdAt;
    final date = created == null
        ? ''
        : reviewDate(created.toUtc().toIso8601String(), locale);
    final title = review.title;
    final text = review.text;
    final product = review.product;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accentSubtle,
                child: Text(
                  reviewerInitials(review.nickname),
                  style: t.micro.copyWith(color: AppColors.accentStrong),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong.copyWith(
                        color: context.scaffoldHeading,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (review.rating != null) ...[
                          ReviewStars(stars: review.stars),
                          const SizedBox(width: 8),
                        ],
                        if (date.isNotEmpty)
                          Text(
                            date,
                            style: t.caption.copyWith(
                              color: context.scaffoldMuted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (title != null) ...[
            const SizedBox(height: 10),
            Text(
              title,
              style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
            ),
          ],
          if (text != null) ...[
            const SizedBox(height: 4),
            Text(
              text,
              style: t.body.copyWith(color: context.scaffoldHeading),
            ),
          ],
          if (product != null) ...[
            const SizedBox(height: 10),
            _ReviewedProduct(product: product),
          ],
        ],
      ),
    );
  }
}

/// The reviewed product as a small tinted row: thumbnail and name.
class _ReviewedProduct extends StatelessWidget {
  const _ReviewedProduct({required this.product});

  final StoreReviewProduct product;

  @override
  Widget build(BuildContext context) {
    final urlKey = product.urlKey;
    final row = Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 40,
              child: HubImage(
                url: product.thumbnailUrl,
                decodeWidth: 40,
                placeholder: (_) =>
                    const ColoredBox(color: AppColors.surfaceTint),
                error: (_) => const ColoredBox(
                  color: AppColors.surfaceTint,
                  child: Icon(
                    HubIcons.image,
                    size: 16,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.of(
                context,
              ).caption.copyWith(color: context.scaffoldHeading),
            ),
          ),
          if (urlKey != null) ...[
            const SizedBox(width: 6),
            // chevron_right mirrors itself in RTL.
            Icon(HubIcons.chevronRight, size: 18, color: context.scaffoldMuted),
          ],
        ],
      ),
    );
    return Material(
      color: groupedPageColor(context),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: urlKey == null
          ? row
          : InkWell(
              onTap: () => context.push(AppRoutes.product(urlKey)),
              child: row,
            ),
    );
  }
}
