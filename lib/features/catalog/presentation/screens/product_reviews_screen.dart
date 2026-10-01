import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/not_found_state.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/review_subject.dart';
import '../reviews_controllers.dart';
import '../widgets/review_widgets.dart';

/// All of a product's published reviews (Figma 15), reached from the product
/// page's "See all". Pages through core `products { reviews }` 20 at a time
/// as the list scrolls.
///
/// From the frame: the summary card, the star filters, the review list and
/// "Write a review" in the footer. Left out because core reviews carry none of
/// it: "With photos", verified-purchase badges, the variant line, helpful votes
/// and store replies. The per-star bars and filters appear only once every
/// review is loaded, so they are counts, never an extrapolation.
class ProductReviewsScreen extends ConsumerStatefulWidget {
  const ProductReviewsScreen({super.key, required this.urlKey});

  final String urlKey;

  @override
  ConsumerState<ProductReviewsScreen> createState() =>
      _ProductReviewsScreenState();
}

class _ProductReviewsScreenState extends ConsumerState<ProductReviewsScreen> {
  final ScrollController _scroll = ScrollController();

  /// Star filter; null = all. Offered only over the complete set.
  int? _stars;

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
      ref
          .read(productReviewsControllerProvider(widget.urlKey).notifier)
          .loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(productReviewsControllerProvider(widget.urlKey));
    final product = state.product;

    // The frame has no tab bar: a footer with "Write a review" instead.
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: RuledTopBar(title: l10n.reviewsScreenTitle),
      bottomNavigationBar: product == null
          ? null
          : ScreenFooter(
              child: HubButton(
                label: l10n.reviewsWrite,
                icon: HubIcons.pencil,
                style: HubButtonStyle.outline,
                onPressed: () => context.push(
                  AppRoutes.review(product.sku),
                  extra: ReviewSubject(sku: product.sku, name: product.name),
                ),
              ),
            ),
      body: _body(l10n, state),
    );
  }

  Widget _body(AppLocalizations l10n, ProductReviewsState state) {
    if (state.isLoading && state.product == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.notFound) return const NotFoundState();
    final product = state.product;
    if (product == null) {
      final error = state.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is Failure
                    ? failureMessage(context, error)
                    : l10n.errorGeneric,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: ref
                    .read(
                      productReviewsControllerProvider(widget.urlKey).notifier,
                    )
                    .refresh,
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (product.reviewCount == 0 && state.reviews.isEmpty) {
      return EmptyState(
        icon: HubIcons.messageSquareText,
        title: l10n.reviewsEmptyTitle,
        body: l10n.reviewsEmptyBody,
      );
    }

    final histogram = state.histogram;
    final starFilters = [
      for (final bar in histogram)
        if (bar.count > 0) bar.stars,
    ];
    final stars = starFilters.contains(_stars) ? _stars : null;
    final visible = stars == null
        ? state.reviews
        : state.reviews.where((r) => r.stars == stars).toList();

    // Figma "Body": 16 px above and around, 14 px between the blocks.
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        ReviewsSummaryCard(
          ratingSummary: product.ratingSummary,
          reviewCount: product.reviewCount,
          histogram: histogram,
        ),
        if (starFilters.length > 1) ...[
          const SizedBox(height: 14),
          _StarFilters(
            stars: starFilters,
            selected: stars,
            allLabel: l10n.filterAll,
            onSelected: (value) => setState(() => _stars = value),
          ),
        ],
        const SizedBox(height: 14),
        for (final review in visible) ReviewCard(review: review),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// "All" plus one chip per star level that has reviews (Figma "Chip": a 36 px
/// pill, 14 px padding, Body Strong — white with a `border/strong` outline,
/// navy and white once chosen), 8 px apart. The frame's "With photos" is left
/// out: core reviews carry no photos.
class _StarFilters extends StatelessWidget {
  const _StarFilters({
    required this.stars,
    required this.selected,
    required this.allLabel,
    required this.onSelected,
  });

  final List<int> stars;
  final int? selected;
  final String allLabel;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    Widget chip(String label, int? value) {
      final on = selected == value;
      final color = on ? Colors.white : AppColors.inkHeading;
      return Padding(
        key: ValueKey('review-filter-${value ?? 'all'}'),
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Semantics(
          button: true,
          selected: on,
          child: Material(
            color: on ? AppColors.brandPrimary : Colors.white,
            shape: StadiumBorder(
              side: on
                  ? BorderSide.none
                  : const BorderSide(color: AppColors.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(value),
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: t.bodyStrong.copyWith(color: color)),
                      // A glyph, not "★": the Arabic font has no star.
                      if (value != null)
                        StarGlyph(size: 14, color: color),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(allLabel, null),
          for (final s in stars) chip('$s', s),
        ],
      ),
    );
  }
}
