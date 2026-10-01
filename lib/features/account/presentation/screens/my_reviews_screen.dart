import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/load_failure_view.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../catalog/domain/review_pages.dart';
import '../../../catalog/presentation/reviews_controllers.dart';
import '../../../catalog/presentation/widgets/review_widgets.dart' show reviewDate;
import '../../../../app/theme/hub_icons.dart';

/// My product reviews (Figma 20f): the reviews the signed-in customer wrote,
/// with the product each is about (core `customer { reviews }`, paged).
///
/// No Pending / Published badge: the customer list includes reviews still
/// awaiting approval, but core `ProductReview` has no status field, so the
/// line above the cards explains moderation instead of labelling each card.
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
      // Figma: a pushed page, no tab bar.
      showTabBar: false,
      appBar: subpageAppBar(context, l10n.myReviewsTitle),
      body: ColoredBox(
        color: groupedPageColor(context),
        child: signedIn
            ? _body(l10n, state)
            : EmptyState(
                icon: HubIcons.messageSquareText,
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
        icon: HubIcons.messageSquareText,
        title: l10n.reviewsEmptyTitle,
        body: l10n.myReviewsEmptyBody,
      );
    }
    final count = state.count;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      children: [
        Text(
          count == null
              ? l10n.myReviewsApprovalNote
              // "3 reviews · reviews are published after a quick check": the
              // note continues the sentence, so it starts in lower case.
              : '${l10n.myReviewsCount(count)} · ${_lowerFirst(l10n.myReviewsApprovalNote)}',
          style: AppTextStyles.of(
            context,
          ).caption.copyWith(color: context.scaffoldMuted),
        ),
        const SizedBox(height: 12),
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
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final review = item.review;
    final date = reviewDate(review.date, locale);
    final urlKey = item.productUrlKey;
    // Figma `review`: 14 px of padding, 8 between the product row, the title
    // and the text; 10 between the photo and the product.
    return Material(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: urlKey == null || urlKey.isEmpty
            ? null
            : () => context.push(AppRoutes.product(urlKey)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            const ColoredBox(color: AppColors.surfaceSubtle),
                        error: (_) => const ColoredBox(
                          color: AppColors.surfaceSubtle,
                          child: Icon(
                            HubIcons.image,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyStrong.copyWith(
                            color: context.scaffoldHeading,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            _Stars(stars: review.stars),
                            if (date.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                date,
                                style: t.caption.copyWith(
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
                const SizedBox(height: 8),
                Text(
                  review.summary.trim(),
                  style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
                ),
              ],
              if (review.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  review.text.trim(),
                  style: t.caption.copyWith(
                    color: context.isDarkMode
                        ? context.scaffoldMuted
                        : AppColors.inkSubtle,
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

/// The rating as the frame draws it: five 11 px stars 2 px apart, the lit ones
/// `rating-star` yellow, the rest `rating-empty` grey.
class _Stars extends StatelessWidget {
  const _Stars({required this.stars});

  final int stars;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 1; i <= 5; i++) ...[
        if (i > 1) const SizedBox(width: 2),
        Icon(
          Icons.star_rounded,
          size: 11,
          color: i <= stars ? AppColors.ratingStar : AppColors.ratingEmpty,
        ),
      ],
    ],
  );
}

/// [text] with its first letter in lower case, to carry on a sentence; Arabic,
/// which has no case, comes back as it is.
String _lowerFirst(String text) =>
    text.isEmpty ? text : text[0].toLowerCase() + text.substring(1);
