import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/category.dart';
import '../../domain/product.dart';
import '../catalog_providers.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../widgets/category_circle.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';
import '../widgets/sort_sheet.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../app/theme/hub_icons.dart';

/// Product listing for a category: aggregation-driven filters, sort, and
/// append-on-scroll pagination.
class PlpScreen extends ConsumerStatefulWidget {
  const PlpScreen({super.key, required this.categoryUid, this.title});

  final String categoryUid;
  final String? title;

  @override
  ConsumerState<PlpScreen> createState() => _PlpScreenState();
}

class _PlpScreenState extends ConsumerState<PlpScreen> {
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

  PlpController get _controller =>
      ref.read(plpControllerProvider(widget.categoryUid).notifier);

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _controller.loadMore();
    }
  }

  /// A page landed — warm the first cards of it while the user is still
  /// scrolling toward them. Bounded: the rest of the page loads as it scrolls
  /// into view, which is what a lazy grid is for.
  void _warmAppendedPage(int previousCount, List<Product> products) {
    if (products.length <= previousCount) return;
    unawaited(
      prefetchImages(
        context,
        products.skip(previousCount).map((p) => p.imageUrl),
        // Two columns with 16pt gutters — the width a card decodes at.
        decodeWidth: HubImage.decodePixels(
          context,
          (MediaQuery.sizeOf(context).width - 48) / 2,
        ),
        limit: 6,
      ),
    );
  }

  Future<void> _openFilters(PlpState state) async {
    final currency = ref.read(storeControllerProvider).currency;
    final result = await showHubBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => FilterSheet(
        aggregations: state.aggregations,
        initial: state.selectedFilters,
        currency: currency,
        initialPriceFrom: state.priceFrom,
        initialPriceTo: state.priceTo,
        initialMinDiscount: state.minDiscount,
        initialMinRating: state.minRating,
      ),
    );
    if (result != null) {
      _controller.applyFilters(
        result.attributes,
        priceFrom: result.priceFrom,
        priceTo: result.priceTo,
        minDiscount: result.minDiscount,
        minRating: result.minRating,
      );
    }
  }

  Future<void> _openSort(PlpState state) async {
    final selected = await showHubBottomSheet<ProductSortField>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SortSheet(current: state.sort),
    );
    if (selected != null) _controller.setSort(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Warm the top of each appended page as it arrives — the grid is 400px
    // from the bottom when loadMore fires, so the images have a head start.
    ref.listen(plpControllerProvider(widget.categoryUid), (previous, next) {
      _warmAppendedPage(previous?.products.length ?? 0, next.products);
    });
    final state = ref.watch(plpControllerProvider(widget.categoryUid));
    // Sub-category chips come from the parent category's navigable children.
    final parent = ref
        .watch(categoryByUidProvider(widget.categoryUid))
        .valueOrNull;
    final subcats = (parent?.children ?? const <Category>[])
        .where((c) => c.includeInMenu)
        .toList(growable: false);
    return HubScaffold(
      currentTab: AppTab.categories,
      body: _body(l10n, state, subcats),
    );
  }

  Widget _body(AppLocalizations l10n, PlpState state, List<Category> subcats) {
    if (state.isLoading && state.products.isEmpty) {
      // Keep the title stable and show shaped card placeholders.
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
            child: Text(
              widget.title ?? l10n.navCategories,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, thickness: 1, color: context.hairline),
          const ProductGridSkeleton(count: 6),
        ],
      );
    }
    if (state.error != null && state.products.isEmpty) {
      final error = state.error;
      // Figma S3 is drawn on this very screen.
      if (isNetworkFailure(error) || ref.watch(isOfflineProvider)) {
        return OfflineState(onRetry: _controller.refresh);
      }
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
                onPressed: _controller.refresh,
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(
          child: _Header(
            title: widget.title ?? l10n.navCategories,
            state: state,
            subcats: subcats,
            onFilters: () => _openFilters(state),
            onSort: () => _openSort(state),
          ),
        ),
        if (state.products.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: HubIcons.package,
              title: l10n.stateEmpty,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: productGridDelegate(context),
              delegate: SliverChildBuilderDelegate((context, index) {
                final product = state.products[index];
                return ProductCard(
                  product: product,
                  onTap: () => openProduct(context, product),
                );
              }, childCount: state.products.length),
            ),
          ),
        if (state.isLoadingMore)
          const SliverToBoxAdapter(
            child: ProductGridSkeleton(count: 2),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.state,
    required this.subcats,
    required this.onFilters,
    required this.onSort,
  });

  final String title;
  final PlpState state;
  final List<Category> subcats;
  final VoidCallback onFilters;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filtersLabel = state.activeFilterCount > 0
        ? '${l10n.filtersLabel} (${state.activeFilterCount})'
        : l10n.filtersLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Divider(height: 1, thickness: 1, color: context.hairline),
        // The category's children as photo circles (CL042-DEV14), matching
        // the storefront's `beauty-subcats` rail — which it draws on every
        // category page that has children, the top level included.
        //
        // Tapping one *navigates* to that category's own listing rather than
        // filtering in place, so each level is a real page with its own rail,
        // its own product count and its own back step — the way the site works.
        if (subcats.isNotEmpty) ...[
          // Breathing room under the title's rule — the circles sat flush
          // against it. Kept here rather than inside the rail so the rail's
          // geometry stays exactly home's Shop by Category.
          const SizedBox(height: 14),
          CategoryCircleRail(
            categories: subcats,
            onTap: (category) => context.push(
              AppRoutes.category(category.uid),
              extra: category.name,
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.categoryProductCount(state.totalCount),
                  style: TextStyle(
                    color: context.scaffoldMuted,
                    fontSize: 12.5,
                  ),
                ),
              ),
              // Two separate controls — Sort and Filter (QA 86d3m97au).
              _PillButton(
                icon: HubIcons.arrowUpDown,
                label: l10n.sortLabel,
                onTap: onSort,
              ),
              const SizedBox(width: 8),
              _PillButton(
                icon: HubIcons.slidersHorizontal,
                label: filtersLabel,
                onTap: onFilters,
              ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: context.hairline),
      ],
    );
  }
}

/// Outlined pill shell shared by the Sort and Filters buttons.
class _Pill extends StatelessWidget {
  const _Pill({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(color: context.hairline),
      borderRadius: BorderRadius.circular(999),
    ),
    child: child,
  );
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(999),
    child: _Pill(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // White in dark mode — these pills sit on the scaffold, so the ink
          // colour was invisible on dark (QA: filter/sort tabs need white).
          Icon(icon, size: 16, color: context.scaffoldHeading),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.scaffoldHeading,
            ),
          ),
        ],
      ),
    ),
  );
}
