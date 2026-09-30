import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../l10n/l10n.dart';
import '../../../stores/presentation/search_vendors.dart';
import '../../../stores/presentation/stores_providers.dart';
import '../../../stores/presentation/widgets/search_vendor_widgets.dart';
import '../../data/algolia/algolia_search.dart' show kAlgoliaCategoryIds;
import '../../domain/aggregation.dart';
import '../../domain/search_facets.dart';
import '../../domain/search_results.dart';
import '../product_navigation.dart';
import '../search_controller.dart';
import 'filter_sheet.dart';
import 'product_card.dart';
import 'product_skeletons.dart';
import 'search_no_results.dart';
import 'search_style.dart';
import 'search_type_ahead.dart' show openSearchCategory;
import 'sort_sheet.dart';

/// Full results of a submitted search (Figma 09c): "Products (N)",
/// "Vendors (V)" and "Categories (M)" tabs. Products carries the result
/// count, the Sort and Filter sheets, the best-matching seller's card and the
/// paged grid; Vendors lists the sellers the search found (see
/// [searchVendorsFrom]); Categories lists the categories the results fall
/// into, each opening its listing.
///
/// On Algolia the pages are Algolia's, the sorts are the replicas configured
/// in Magento (relevance first) and the filters are the index's facets with
/// their store-view labels; on the GraphQL fallback they are GraphQL's.
///
/// The Vendors tab and the seller card need the Hub Market App's seller API:
/// without it ([storesAvailableProvider] off) the page keeps its two tabs. A
/// search that finds nothing at all (no product, and no store by that name)
/// shows the no-results page (Figma S2) instead of the tabs.
class SearchResultsView extends ConsumerWidget {
  const SearchResultsView({
    super.key,
    required this.request,
    this.scopeName,
    this.onSearch,
  });

  final SearchRequest request;

  /// Name of the category the search is scoped to, for the results line.
  final String? scopeName;

  /// Submits another search (a no-results "Try" chip).
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchResultsProvider(request));
    final stores = ref.watch(storesAvailableProvider);
    final vendors = stores ? ref.watch(searchVendorsProvider(request)) : null;
    final vendorList = vendors?.valueOrNull ?? const <SearchVendor>[];
    final vendorsCounted = vendors?.hasValue ?? false;

    // Emptied by its own filters, a search keeps its tabs so the filters can
    // be changed back; one that found nothing at all gets the S2 page, unless
    // it names a store, which then opens on the Vendors tab.
    final foundNothing =
        !state.isLoading &&
        state.error == null &&
        state.products.isEmpty &&
        state.filters.isEmpty;
    var initialTab = 0;
    if (foundNothing) {
      if (vendors == null || (vendorsCounted && vendorList.isEmpty)) {
        return SearchNoResults(query: request.query, onTry: onSearch);
      }
      if (!vendorsCounted) {
        return const Center(child: CircularProgressIndicator());
      }
      initialTab = 1;
    }

    final counted = !state.isLoading || state.products.isNotEmpty;
    return DefaultTabController(
      // A new search starts on its first tab.
      key: ValueKey((request, stores, initialTab)),
      length: stores ? 3 : 2,
      initialIndex: initialTab,
      child: Column(
        children: [
          _ResultTabs(
            products: counted
                ? l10n.searchTabProducts(state.totalCount)
                : l10n.searchProductsHeading,
            vendors: !stores
                ? null
                : vendorsCounted
                ? l10n.searchTabVendors(vendorList.length)
                : l10n.searchVendorsLabel,
            categories: counted
                ? l10n.searchTabCategories(state.categories.length)
                : l10n.searchCategoriesLabel,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ProductsTab(
                  request: request,
                  scopeName: scopeName,
                  vendor: vendorList.firstOrNull,
                ),
                if (stores)
                  SearchVendorsTab(
                    query: request.query,
                    vendors: vendorList,
                    loading: !vendorsCounted,
                  ),
                _CategoriesTab(
                  query: request.query,
                  categories: state.categories,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The name of a sort in the app's words, or the admin's label for a replica
/// the app has no wording for.
String searchSortLabel(AppLocalizations l10n, SearchSortOption option) {
  final sort = option.sort;
  if (sort.isRelevance) return l10n.sortRelevance;
  return switch ((sort.attribute, sort.descending)) {
    ('price', false) => l10n.sortPriceLowHigh,
    ('price', true) => l10n.sortPriceHighLow,
    ('created_at', true) => l10n.sortNewest,
    ('name', false) => l10n.sortNameAz,
    _ => option.label.isNotEmpty ? option.label : sort.attribute,
  };
}

/// The underlined tab row: orange 3 pt indicator under the active label.
class _ResultTabs extends StatelessWidget {
  const _ResultTabs({
    required this.products,
    required this.categories,
    this.vendors,
  });

  final String products;
  final String categories;

  /// The Vendors tab's label; null leaves the tab out.
  final String? vendors;

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
        if (vendors != null) Tab(height: 41, text: vendors),
        Tab(height: 41, text: categories),
      ],
    );
  }
}

/// Products tab: "N results for “q”" with the Sort and Filter actions, then
/// the product grid, paging on scroll.
class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab({required this.request, this.scopeName, this.vendor});

  final SearchRequest request;
  final String? scopeName;

  /// The seller the search found first, carded above the grid.
  final SearchVendor? vendor;

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
      ref.read(searchResultsProvider(widget.request).notifier);

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

  /// The facets as the Filter sheet shows them: a section Magento sent
  /// without a label gets the app's name for it.
  List<Aggregation> _sheetFacets(
    AppLocalizations l10n,
    List<Aggregation> facets,
  ) => [
    for (final facet in facets)
      facet.label.trim().isNotEmpty
          ? facet
          : Aggregation(
              attributeCode: facet.attributeCode,
              label: switch (facet.attributeCode) {
                kAlgoliaCategoryIds ||
                kCategoryAggregationCode => l10n.searchCategoriesLabel,
                'price' => l10n.filterPriceLabel,
                _ => facet.attributeCode,
              },
              options: facet.options,
            ),
  ];

  Future<void> _openFilters(SearchResultsState state) async {
    final l10n = AppLocalizations.of(context);
    final currency = ref.read(storeControllerProvider).currency;
    final filters = state.filters;
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => FilterSheet(
        aggregations: _sheetFacets(l10n, state.facets),
        initial: filters.attributes,
        currency: currency,
        initialPriceFrom: filters.priceFrom,
        initialPriceTo: filters.priceTo,
        initialMinRating: filters.minRating,
        showDiscount: false,
        showRating: state.ratingFilter,
      ),
    );
    if (result == null || !mounted) return;
    _notifier.applyFilters(
      SearchFilters(
        attributes: result.attributes,
        priceFrom: result.priceFrom,
        priceTo: result.priceTo,
        minRating: state.ratingFilter ? result.minRating : null,
      ),
    );
  }

  Future<void> _openSort(SearchResultsState state) async {
    final l10n = AppLocalizations.of(context);
    final options = state.sorts.isNotEmpty
        ? state.sorts
        : const [SearchSortOption(SearchSort.relevance)];
    final selected = await showModalBottomSheet<SearchSort>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SortChoiceSheet<SearchSort>(
        current: state.sort,
        choices: [
          for (final option in options)
            (value: option.sort, label: searchSortLabel(l10n, option)),
        ],
      ),
    );
    if (selected != null && mounted) _notifier.setSort(selected);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchResultsProvider(widget.request));
    final activeFilters = state.filters.count;
    final meta = _MetaRow(
      summary: _summary(l10n, state.totalCount),
      sortLabel: _sortLabel(l10n, state),
      filterLabel: activeFilters > 0
          ? '${l10n.searchFilterAction} ($activeFilters)'
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

    final vendor = widget.vendor;
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverToBoxAdapter(child: meta),
        if (vendor != null)
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 10),
            sliver: SliverToBoxAdapter(child: SearchVendorCard(vendor: vendor)),
          ),
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
                // The card's "+" adds a simple product by SKU; for a
                // configurable it opens the product page, as a tap does.
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
  String _sortLabel(AppLocalizations l10n, SearchResultsState state) {
    for (final option in state.sorts) {
      if (option.sort == state.sort) return searchSortLabel(l10n, option);
    }
    return searchSortLabel(l10n, SearchSortOption(state.sort));
  }
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
