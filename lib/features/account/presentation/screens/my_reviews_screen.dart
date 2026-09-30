import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/load_failure_view.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../catalog/domain/review_pages.dart';
import '../../../catalog/presentation/reviews_controllers.dart';
import '../../../catalog/presentation/widgets/review_widgets.dart';

/// My product reviews (Figma 20f): the reviews the signed-in customer wrote,
/// with the product each is about (core `customer { reviews }`, paged).
///
/// No Pending / Published badge: the customer list includes reviews still
/// awaiting approval, but core `ProductReview` has no status field, so the
/// line under the title explains moderation instead of labelling each card.
class MyReviewsScreen extends ConsumerStatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  ConsumerState<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends ConsumerState<MyReviewsScreen> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(myReviewsControllerProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signedIn = ref.watch(
      authControllerProvider.select((s) => s.isAuthenticated),
    );
    final state = ref.watch(myReviewsControllerProvider);
    return HubScaffold(
      currentTab: AppTab.account,
      appBar: subpageAppBar(context, l10n.myReviewsTitle),
      body: ColoredBox(
        color: groupedPageColor(context),
        child: signedIn
            ? _body(l10n, state)
            : EmptyState(
                icon: Icons.rate_review_outlined,
                title: l10n.myReviewsTitle,
                body: l10n.myReviewsSignIn,
                action: FilledButton(
                  onPressed: () => context.push(AppRoutes.signIn),
                  child: Text(l10n.authSignInTitle),
                ),
              ),
      ),
    );
  }

  Widget _body(AppLocalizations l10n, MyReviewsState state) {
    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = state.error;
    if (error != null && state.items.isEmpty) {
      // Offline: the S3 page, which reloads by itself once the network is back.
      return LoadFailureView(
        error: error,
        onRetry: ref.read(myReviewsControllerProvider.notifier).refresh,
      );
    }
    if (state.items.isEmpty) {
      return EmptyState(
        icon: Icons.rate_review_outlined,
        title: l10n.reviewsEmptyTitle,
        body: l10n.myReviewsEmptyBody,
      );
    }
    final count = state.count;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 2, bottom: 10),
          child: Text(
            count == null
                ? l10n.myReviewsApprovalNote
                : '${l10n.myReviewsCount(count)} · ${l10n.myReviewsApprovalNote}',
            style: TextStyle(fontSize: 12.5, color: context.scaffoldMuted),
          ),
        ),
        for (final item in state.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MyReviewCard(item: item),
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  const _MyReviewCard({required this.item});

  final CustomerReview item;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final review = item.review;
    final date = reviewDate(review.date, locale);
    final urlKey = item.productUrlKey;
    return Material(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: urlKey == null || urlKey.isEmpty
            ? null
            : () => context.push(AppRoutes.product(urlKey)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: HubImage(
                        url: item.productImageUrl,
                        decodeWidth: 48,
                        placeholder: (_) =>
                            const ColoredBox(color: AppColors.surfaceTint),
                        error: (_) => const ColoredBox(
                          color: AppColors.surfaceTint,
                          child: Icon(
                            Icons.image_outlined,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: context.scaffoldHeading,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                const SizedBox(height: 12),
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
                const SizedBox(height: 6),
                Text(
                  review.text.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.scaffoldMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
