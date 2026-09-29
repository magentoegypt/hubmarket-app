import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/search_facets.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../search_controller.dart';
import '../search_providers.dart';
import 'filter_sheet.dart';
import 'product_card.dart';
import 'product_skeletons.dart';
import 'search_no_results.dart';
import 'search_style.dart';
import 'search_type_ahead.dart' show openSearchCategory;
import 'sort_sheet.dart';

/// Full results of a submitted search (Figma 09c): "Products (N)" and
/// "Categories (M)" tabs. Products carries the result count, the Relevance sort
/// and Filter sheets and the paged grid; Categories lists the categories the
/// results fall into, each opening its listing.
///
/// The frame's Vendors tab and matching-vendor card need a public vendor API,
/// which is Build 2, so both are left out. A search that finds nothing at all
/// shows the no-results page (Figma S2) instead of the tabs.
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({super.key, required this.request, this.scopeName});

  final SearchRequest request;

  /// Name of the category the search is scoped to, for the results line.
  final String? scopeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider(request));
    final categories = ref.watch(searchResultCategoriesProvider(request));

    // Emptied by its own filters, a search keeps its tabs so the filters can
    // be changed back; one that found nothing at all gets the S2 page.
    final foundNothing =
        !state.isLoading &&
        state.error == null &&
        state.products.isEmpty &&
        state.activeFilterCount == 0;
    if (foundNothing) return SearchNoResults(query: request.query);

    final counted = !state.isLoading || state.products.isNotEmpty;
    return DefaultTabController(
      // A new search starts on the Products tab.
      key: ValueKey(request),
      length: 2,
      child: Column(
        children: [
          _ResultTabs(
            products: counted
                ? l10n.searchTabProducts(state.totalCount)
                : l10n.searchProductsHeading,
            categories: counted
                ? l10n.searchTabCategories(categories.length)
                : l10n.searchCategoriesLabel,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ProductsTab(request: request, scopeName: scopeName),
                _CategoriesTab(query: request.query, categories: categories),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The underlined tab row: orange 3 pt indicator under the active label.
class _ResultTabs extends StatelessWidget {
  const _ResultTabs({required this.products, required this.categories});

  final String products;
  final String categories;

  @override
  Widget build(BuildContext context) {
    return TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      padding: const EdgeInsetsDirectional.only(start: 16),
      labelPadding: const EdgeInsetsDirectional.only(end: 20),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: const UnderlineTabIndicator(
        borderSide: BorderSide(color: AppColors.accent, width: 3),
      ),
      dividerColor: context.hairline,
      labelColor: context.scaffoldHeading,
      unselectedLabelColor: context.scaffoldMuted,
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      tabs: [
        Tab(height: 41, text: products),
        Tab(height: 41, text: categories),
      ],
    );
  }
}

/// Products tab: "N results for “q”" with the Relevance sort and Filter
/// actions, then the product grid, paging on scroll.
class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab({required this.request, this.scopeName});

  final SearchRequest request;
  final String? scopeName;

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();

  // Keeps the grid's scroll position while the Categories tab is open.
  @override
  bool get wantKeepAlive => true;

  SearchResultsController get _notifier =>
      ref.read(searchControllerProvider(widget.request).notifier);

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
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _notifier.loadMore();
    }
  }

  Future<void> _openFilters(PlpState state) async {
    final currency = ref.read(storeControllerProvider).currency;
    final result = await showModalBottomSheet<FilterResult>(
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
    if (result == null || !mounted) return;
    _notifier.applyFilters(
      result.attributes,
      priceFrom: result.priceFrom,
      priceTo: result.priceTo,
      minDiscount: result.minDiscount,
      minRating: result.minRating,
    );
  }

  Future<void> _openSort(PlpState state) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<ProductSortField>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) =>
          SortSheet(current: state.sort, relevanceLabel: l10n.sortRelevance),
    );
    if (selected != null && mounted) _notifier.setSort(selected);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider(widget.request));
    final meta = _MetaRow(
      summary: _summary(l10n, state.totalCount),
      sortLabel: _sortLabel(l10n, state.sort),
      filterLabel: state.activeFilterCount > 0
          ? '${l10n.searchFilterAction} (${state.activeFilterCount})'
          : l10n.searchFilterAction,
      onSort: () => _openSort(state),
      onFilter: () => _openFilters(state),
    );

    if (state.isLoading && state.products.isEmpty) {
      return ListView(
        children: [
          meta,
          const ProductGridSkeleton(childAspectRatio: 0.58, count: 6),
        ],
      );
    }

    final error = state.error;
    if (error != null && state.products.isEmpty) {
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
                onPressed: _notifier.refresh,
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
        SliverToBoxAdapter(child: meta),
        if (state.products.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(
              icon: Icons.search_off_outlined,
              title: l10n.stateEmpty,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.58,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
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
            child: ProductGridSkeleton(childAspectRatio: 0.58, count: 2),
          ),
      ],
    );
  }

  String _summary(AppLocalizations l10n, int count) {
    final scope = widget.scopeName;
    final query = isolateQuery(widget.request.query);
    return scope == null
        ? l10n.searchResultsSummary(count, query)
        : l10n.searchResultsSummaryIn(count, query, scope);
  }

  /// The active sort, named — "Relevance" until the shopper picks another.
  String _sortLabel(AppLocalizations l10n, ProductSortField sort) =>
      switch (sort) {
        ProductSortField.relevance => l10n.sortRelevance,
        ProductSortField.priceAsc => l10n.sortPriceLowHigh,
        ProductSortField.priceDesc => l10n.sortPriceHighLow,
        ProductSortField.nameAsc => l10n.sortNameAz,
      };
}

/// "12 results for “sofa”" · ⇅ Relevance · Filter.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.summary,
    required this.sortLabel,
    required this.filterLabel,
    required this.onSort,
    required this.onFilter,
  });

  final String summary;
  final String sortLabel;
  final String filterLabel;
  final VoidCallback onSort;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 12 at the end: the Filter action's own 4 pt padding makes up the 16.
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 16 / 12,
                color: context.scaffoldMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _MetaAction(icon: Icons.swap_vert, label: sortLabel, onTap: onSort),
          const SizedBox(width: 6),
          _MetaAction(icon: Icons.tune, label: filterLabel, onTap: onFilter),
        ],
      ),
    );
  }
}

class _MetaAction extends StatelessWidget {
  const _MetaAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.scaffoldHeading;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        // A 38 pt tall target around the 16 pt line (the frame's row is 10 +
        // 18 + 10).
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            // Capped so a long sort name ("Price: High to Low", or its Arabic)
            // can't push the row past the screen next to a long results line.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Categories tab: the categories the results fall into, with how many of the
/// results each holds. A tap opens the category's listing.
class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({required this.query, required this.categories});

  final String query;
  final List<SearchCategory> categories;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.searchNoCategoryMatches(isolateQuery(query)),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.scaffoldMuted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: categories.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, thickness: 1, indent: 64, color: context.hairline),
      itemBuilder: (context, i) {
        final category = categories[i];
        return InkWell(
          onTap: () => openSearchCategory(context, category.uid, category.name),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: context.isDarkMode
                        ? Colors.white10
                        : AppColors.surfaceTint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.grid_view_outlined,
                    size: 18,
                    color: context.isDarkMode
                        ? Colors.white
                        : AppColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w600,
                          color: context.scaffoldHeading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.searchCategoryMatches(category.count),
                        style: TextStyle(
                          fontSize: 12,
                          height: 16 / 12,
                          color: context.scaffoldMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // chevron_right mirrors itself in RTL.
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.scaffoldMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
