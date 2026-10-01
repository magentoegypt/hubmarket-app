import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/aggregation.dart';
import '../../domain/category.dart';
import '../../domain/product.dart';
import '../catalog_providers.dart';
import '../category_stores.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../widgets/category_circle.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/meta_action.dart';
import '../widgets/plp_filter_bar.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';
import '../widgets/sheet_chrome.dart';
import '../widgets/sort_sheet.dart';

/// Product listing for a category (Figma 10): aggregation-driven filters,
/// sort, and append-on-scroll pagination. The app bar names the category and
/// carries Search and Cart; under it the chip bar (Filters, the filters that
/// are on, quick ones), the results line with the sort, and the grid.
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

  /// The listing's sorts as the Filters sheet names them — the ones the
  /// backend can do. "Newest first" (Figma 11) joins them once it can (see
  /// [kNewestSortSupported]); the sort sheet shows it disabled meanwhile.
  List<SortChoice<Object>> _sortChoices(AppLocalizations l10n) => [
    (value: ProductSortField.relevance, label: l10n.sortRelevance),
    (value: ProductSortField.priceAsc, label: l10n.sortLowestPrice),
    (value: ProductSortField.priceDesc, label: l10n.sortHighestPrice),
    (value: ProductSortField.nameAsc, label: l10n.sortNameAz),
  ];

  /// The sheet's facets: a listing of one category does not filter by
  /// category — its sub-categories are the rail above it.
  List<Aggregation> _sheetFacets(PlpState state) => [
    for (final facet in state.aggregations)
      if (facet.attributeCode != 'category_uid' &&
          facet.attributeCode != 'category_id')
        facet,
  ];

  Future<void> _openFilters(
    PlpState state, {
    Map<String, String>? names,
  }) async {
    final currency = ref.read(storeControllerProvider).currency;
    final result = await showCatalogSheet<FilterResult>(
      context: context,
      builder: (_) => FilterSheet(
        aggregations: _sheetFacets(state),
        initial: state.selectedFilters,
        currency: currency,
        initialPriceFrom: state.priceFrom,
        initialPriceTo: state.priceTo,
        initialMinDiscount: state.minDiscount,
        initialMinRating: state.minRating,
        sortChoices: _sortChoices(AppLocalizations.of(context)),
        initialSort: state.sort,
        resultCount: state.totalCount,
        countFor: (selection) => _controller.countFor(
          attributes: selection.attributes,
          priceFrom: selection.priceFrom,
          priceTo: selection.priceTo,
          minDiscount: selection.minDiscount,
          minRating: selection.minRating,
        ),
        storeNames: names ?? const <String, String>{},
        showHandle: true,
      ),
    );
    if (result != null) {
      _controller.applyFilters(
        result.attributes,
        priceFrom: result.priceFrom,
        priceTo: result.priceTo,
        minDiscount: result.minDiscount,
        minRating: result.minRating,
        sort: result.sort as ProductSortField?,
      );
    }
  }

  Future<void> _openSort(PlpState state) async {
    final selected = await showCatalogSheet<ProductSortField>(
      context: context,
      builder: (_) => SortSheet(current: state.sort, showHandle: true),
    );
    if (selected != null) _controller.setSort(selected);
  }

  /// Takes one value off the filters that are on (a navy chip's tap).
  void _removeValue(PlpState state, String code, String value) {
    final next = {
      for (final entry in state.selectedFilters.entries)
        entry.key: {...entry.value},
    };
    next[code]?.remove(value);
    if (next[code]?.isEmpty ?? false) next.remove(code);
    _controller.applyFilters(
      next,
      priceFrom: state.priceFrom,
      priceTo: state.priceTo,
      minDiscount: state.minDiscount,
      minRating: state.minRating,
    );
  }

  void _removePrice(PlpState state) => _controller.applyFilters(
    state.selectedFilters,
    minDiscount: state.minDiscount,
    minRating: state.minRating,
  );

  /// The chips after Filters: what is on, then the quick ones.
  List<PlpChip> _chips(
    AppLocalizations l10n,
    PlpState state,
    Map<String, String> names,
  ) {
    final currency = ref.read(storeControllerProvider).currency;
    final chips = <PlpChip>[];
    for (final entry in state.selectedFilters.entries) {
      for (final value in entry.value) {
        chips.add(
          PlpChip(
            label: _valueLabel(state, entry.key, value, names),
            selected: true,
            onTap: () => _removeValue(state, entry.key, value),
          ),
        );
      }
    }
    if (state.hasPriceFilter) {
      final from = state.priceFrom;
      final to = state.priceTo;
      chips.add(
        PlpChip(
          label: from != null && to != null
              ? '$currency ${from.round()} – ${to.round()}'
              : '$currency ${(from ?? to)!.round()}${from != null ? '+' : ' –'}',
          selected: true,
          onTap: () => _removePrice(state),
        ),
      );
    } else if (state.aggregations.any((a) => a.attributeCode == 'price')) {
      chips.add(
        PlpChip(
          label: l10n.filterPriceLabel,
          onTap: () => _openFilters(state, names: names),
        ),
      );
    }
    final rating = state.minRating;
    if (rating != null) {
      chips.add(
        PlpChip(
          label: l10n.filterRatingChip('$rating'),
          selected: true,
          onTap: () => _controller.applyFilters(
            state.selectedFilters,
            priceFrom: state.priceFrom,
            priceTo: state.priceTo,
            minDiscount: state.minDiscount,
          ),
        ),
      );
    } else if (kRatingFilterSupported) {
      chips.add(
        PlpChip(
          label: l10n.filterRatingChip('4'),
          onTap: () => _controller.applyFilters(
            state.selectedFilters,
            priceFrom: state.priceFrom,
            priceTo: state.priceTo,
            minDiscount: state.minDiscount,
            minRating: 4,
          ),
        ),
      );
    }
    final discount = state.minDiscount;
    if (discount != null) {
      chips.add(
        PlpChip(
          label: l10n.filterDiscountOption(discount),
          selected: true,
          onTap: () => _controller.applyFilters(
            state.selectedFilters,
            priceFrom: state.priceFrom,
            priceTo: state.priceTo,
            minRating: state.minRating,
          ),
        ),
      );
    }
    return chips;
  }

  /// What a chip for a facet value says: the option's label, a store's name
  /// for the facets of vendor ids.
  String _valueLabel(
    PlpState state,
    String code,
    String value,
    Map<String, String> names,
  ) {
    for (final facet in state.aggregations) {
      if (facet.attributeCode != code) continue;
      for (final option in facet.options) {
        if (option.value != value) continue;
        return kStoreFacetCodes.contains(code)
            ? (names[option.label.trim()] ?? option.label)
            : option.label;
      }
    }
    return value;
  }

  /// "12 products", or "12 products from MIA CO" with one store picked.
  String _count(
    AppLocalizations l10n,
    PlpState state,
    Map<String, String> names,
  ) {
    for (final code in kStoreFacetCodes) {
      final picked = state.selectedFilters[code];
      if (picked != null && picked.length == 1) {
        final store = _valueLabel(state, code, picked.single, names);
        return l10n.categoryProductCountFrom(state.totalCount, store);
      }
    }
    return l10n.categoryProductCount(state.totalCount);
  }

  String _sortLabel(AppLocalizations l10n, ProductSortField sort) =>
      switch (sort) {
        ProductSortField.relevance => l10n.sortRelevance,
        ProductSortField.priceAsc => l10n.sortLowestPrice,
        ProductSortField.priceDesc => l10n.sortHighestPrice,
        ProductSortField.nameAsc => l10n.sortNameAz,
      };

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
    // Store names for the vendor facets — asked only of a listing that has
    // one, and empty without the seller API.
    final hasStoreFacet =
        state.aggregations.any(
          (a) => kStoreFacetCodes.contains(a.attributeCode),
        ) ||
        state.selectedFilters.keys.any(kStoreFacetCodes.contains);
    final names = hasStoreFacet
        ? ref.watch(storeNamesProvider).valueOrNull ??
              const <String, String>{}
        : const <String, String>{};
    return HubScaffold(
      currentTab: AppTab.categories,
      appBar: HubTopBar(
        title: widget.title ?? parent?.name ?? l10n.navCategories,
        actions: [
          HubIconButton(
            icon: HubIcons.search,
            tooltip: l10n.searchHint,
            onPressed: () => context.push(AppRoutes.search),
          ),
          HubIconButton(
            icon: HubIcons.shoppingCart,
            tooltip: l10n.navCart,
            onPressed: () => context.go(AppRoutes.cart),
          ),
        ],
      ),
      body: _body(l10n, state, subcats, names),
    );
  }

  Widget _body(
    AppLocalizations l10n,
    PlpState state,
    List<Category> subcats,
    Map<String, String> names,
  ) {
    if (state.isLoading && state.products.isEmpty) {
      // The bar already names the category: shaped card placeholders.
      return ListView(children: const [ProductGridSkeleton(count: 6)]);
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
            // The category's children as photo circles (CL042-DEV14), as the
            // storefront draws them on every category page that has children.
            // Tapping one *navigates* to that category's own listing, so each
            // level is a real page with its own rail, count and back step.
            subcats: subcats,
            activeCount: state.activeFilterCount,
            chips: _chips(l10n, state, names),
            count: _count(l10n, state, names),
            sortLabel: _sortLabel(l10n, state.sort),
            onFilters: () => _openFilters(state, names: names),
            onSort: () => _openSort(state),
          ),
        ),
        if (state.products.isEmpty)
          SliverToBoxAdapter(
            child: EmptyState(icon: HubIcons.package, title: l10n.stateEmpty),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              // Figma 10: 16 between the columns, 20 between the rows.
              gridDelegate: ProductGridDelegate(
                infoHeight: ProductCardMetrics.infoHeight(context),
                mainAxisSpacing: 20,
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
          const SliverToBoxAdapter(child: ProductGridSkeleton(count: 2)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// Everything above the grid: the sub-category rail, the chip bar and the
/// results line with the sort.
class _Header extends StatelessWidget {
  const _Header({
    required this.subcats,
    required this.activeCount,
    required this.chips,
    required this.count,
    required this.sortLabel,
    required this.onFilters,
    required this.onSort,
  });

  final List<Category> subcats;
  final int activeCount;
  final List<PlpChip> chips;
  final String count;
  final String sortLabel;
  final VoidCallback onFilters;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (subcats.isNotEmpty) ...[
          const SizedBox(height: 8),
          CategoryCircleRail(
            categories: subcats,
            onTap: (category) => context.push(
              AppRoutes.category(category.uid),
              extra: category.name,
            ),
          ),
          const SizedBox(height: 4),
        ],
        // 6 here and the sort's own 4 above its line make the frame's 10.
        PlpFilterBar(
          activeCount: activeCount,
          onFilters: onFilters,
          chips: chips,
          bottom: 6,
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 12, 24),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  count,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: context.scaffoldMuted),
                ),
              ),
              const SizedBox(width: 8),
              MetaAction(
                icon: HubIcons.arrowUpDown,
                label: sortLabel,
                onTap: onSort,
                verticalPadding: 4,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
