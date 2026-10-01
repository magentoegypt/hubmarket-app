import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/not_found_state.dart';
import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../l10n/l10n.dart';
import '../reviews_controllers.dart';
import '../widgets/review_widgets.dart';
import '../../../../app/theme/hub_icons.dart';

/// All of a product's published reviews (Figma 15), reached from the product
/// page's "See all". Pages through core `products { reviews }` 20 at a time
/// as the list scrolls.
///
/// From the frame: the summary card, star filters, the review list and
/// "Write a review". Left out because core reviews carry none of it: "With
/// photos", verified-purchase badges, the variant line, helpful votes and
/// store replies. The per-star bars and filters appear only once every
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

    return HubScaffold(
      currentTab: AppTab.home,
      appBar: subpageAppBar(context, l10n.reviewsScreenTitle),
      bottomBar: product == null
          ? null
          : _WriteReviewBar(
              onTap: () => context.push(AppRoutes.review(product.sku)),
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

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
        const SizedBox(height: 4),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: context.hairline),
          ReviewCard(review: visible[i]),
        ],
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

/// "All" plus one chip per star level that has reviews.
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
    Widget chip(String label, int? value) {
      final on = selected == value;
      final color = on ? Colors.white : context.scaffoldHeading;
      return Padding(
        key: ValueKey('review-filter-${value ?? 'all'}'),
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Material(
          color: on ? AppColors.brandPrimary : groupCardColor(context),
          shape: StadiumBorder(
            side: BorderSide(
              color: on ? AppColors.brandPrimary : context.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onSelected(value),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  // An icon, not "★": the Arabic font has no star glyph.
                  if (value != null)
                    Icon(Icons.star_rounded, size: 15, color: color),
                ],
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

/// The pinned "Write a review" action (Figma 15, 15b).
class _WriteReviewBar extends StatelessWidget {
  const _WriteReviewBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(HubIcons.pencil, size: 20),
          label: Text(
            l10n.reviewsWrite,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: context.scaffoldHeading,
            side: BorderSide(color: context.scaffoldHeading, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
