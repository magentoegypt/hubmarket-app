import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/data/catalog_repository.dart' show ProductSortField;
import '../../../catalog/domain/search_facets.dart';
import '../../../catalog/presentation/plp_controller.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/widgets/filter_sheet.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../../catalog/presentation/widgets/product_skeletons.dart';
import '../../../catalog/presentation/widgets/search_style.dart';
import '../../../catalog/presentation/widgets/sort_sheet.dart';
import '../../domain/store.dart';
import '../store_products_controller.dart';
import '../stores_providers.dart';
import '../widgets/store_about.dart';
import '../widgets/store_widgets.dart';
import '../widgets/stores_unavailable.dart';

/// The tabs of a store page, in order.
enum StoreTab { products, about, policies }

/// One seller's store (Figma 13, and 13b for its About tab): the banner with
/// the logo, name and figures, then Products (the seller's catalogue with the
/// PLP's search, filters, sort and paging), About and Policies.
///
/// From `hmStore(code)`; the products are core `products` filtered by the
/// seller's `vendor_id`. A card handed over by the list ([preview]) paints the
/// header and starts the products at once. The frame's Reviews tab, "Contact
/// vendor", favourite and "Call" buttons and the location line have no
/// source in the seller API, so they are left out; Policies shows only when
/// the seller publishes one.
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key, required this.code, this.preview});

  final String code;
  final HmStoreCard? preview;

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final GlobalKey _infoKey = GlobalKey(debugLabel: 'store-info');
  Timer? _debounce;

  StoreTab _tab = StoreTab.products;
  bool _collapsed = false;

  /// The seller whose products are listed, once known.
  int? _vendorId;

  /// The banner, and the white strip the logo overhangs into.
  static const double _bannerHeight = 196;
  static const double _headerHeight = 236;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  StoreProductsController? get _products => _vendorId == null
      ? null
      : ref.read(storeProductsControllerProvider(_vendorId!).notifier);

  void _onScroll() {
    final collapsed = _scroll.offset > _headerHeight - kToolbarHeight - 12;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    if (_tab == StoreTab.products &&
        _scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _products?.loadMore();
    }
  }

  /// Where the tabs pin under the collapsed header.
  double get _tabsPinnedAt {
    final info = _infoKey.currentContext?.size?.height ?? 0;
    return _headerHeight - kToolbarHeight + info;
  }

  void _selectTab(StoreTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    // A tab opens at its top when the page was scrolled past it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pinned = _tabsPinnedAt;
      if (_scroll.offset > pinned) _scroll.jumpTo(pinned);
    });
  }

  /// Back to where the page was opened from; Home when it was the first
  /// screen (a deep link).
  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  void _focusSearch() {
    _selectTab(StoreTab.products);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _products?.setSearch(value);
    });
    setState(() {});
  }

  void _submitSearch(String value) {
    _debounce?.cancel();
    _products?.setSearch(value);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    _products?.setSearch('');
    setState(() {});
  }

  void _showCategory(SearchCategory category) {
    final products = _products;
    if (products == null) return;
    final state = ref.read(storeProductsControllerProvider(_vendorId!));
    products.applyFilters(
      {
        ...state.selectedFilters,
        kCategoryAggregationCode: {category.uid},
      },
      priceFrom: state.priceFrom,
      priceTo: state.priceTo,
    );
    _selectTab(StoreTab.products);
  }

  Future<void> _openFilters(PlpState state) async {
    final products = _products;
    if (products == null) return;
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
      ),
    );
    if (result == null || !mounted) return;
    products.applyFilters(
      result.attributes,
      priceFrom: result.priceFrom,
      priceTo: result.priceTo,
    );
  }

  Future<void> _openSort(PlpState state) async {
    final products = _products;
    if (products == null) return;
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<ProductSortField>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SortSheet(
        current: state.sort,
        relevanceLabel: products.search.isEmpty
            ? l10n.sortFeatured
            : l10n.sortRelevance,
      ),
    );
    if (picked != null && mounted) products.setSort(picked);
  }

  Future<void> _share(HmStoreCard store) async {
    final url = store.webUrl;
    if (url == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: '${AppLocalizations.of(context).storeShare(store.name)}\n$url',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!ref.watch(storesAvailableProvider)) {
      return _plain(context, const StoresUnavailable());
    }
    final loaded = ref.watch(storeProfileProvider(widget.code));
    final error = loaded.error;
    if (error != null && !loaded.isLoading) {
      if (error is HubAppMissing) {
        return _plain(context, const StoresUnavailable());
      }
      void retry() => ref.invalidate(storeProfileProvider(widget.code));
      return _plain(
        context,
        isNetworkFailure(error) || ref.watch(isOfflineProvider)
            ? OfflineState(onRetry: retry)
            : Center(
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
                        onPressed: retry,
                        child: Text(l10n.actionRetry),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }
    if (loaded.hasValue && loaded.value == null) {
      return _plain(
        context,
        EmptyState(
          icon: Icons.storefront_outlined,
          title: l10n.storeNotFoundTitle,
          body: l10n.storeNotFoundBody,
        ),
      );
    }
    final profile =
        loaded.valueOrNull ??
        (widget.preview == null ? null : StoreProfile(card: widget.preview!));
    if (profile == null) {
      return _plain(
        context,
        const Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    _vendorId = profile.card.vendorEntityId;
    return _page(context, l10n, profile);
  }

  /// A state without the store (loading, missing, failed): the scaffold with
  /// a back button over [body].
  Widget _plain(BuildContext context, Widget body) => HubScaffold(
    currentTab: AppTab.home,
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: HubBackButton(onPressed: _back),
    ),
    body: body,
  );

  Widget _page(
    BuildContext context,
    AppLocalizations l10n,
    StoreProfile profile,
  ) {
    final store = profile.card;
    // Watched on every tab, so the search, filters and sort survive a look
    // at About.
    final products = ref.watch(
      storeProductsControllerProvider(store.vendorEntityId),
    );
    final tabs = [
      StoreTab.products,
      StoreTab.about,
      if (profile.hasPolicies) StoreTab.policies,
    ];
    final tab = tabs.contains(_tab) ? _tab : StoreTab.products;
    return HubScaffold(
      currentTab: AppTab.home,
      // The header is the scroll view's own collapsing bar.
      appBar: const PreferredSize(
        preferredSize: Size.zero,
        child: SizedBox.shrink(),
      ),
      body: CustomScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          _header(context, l10n, profile),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _infoKey,
              child: _StoreInfo(profile: profile),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              tabs: tabs,
              selected: tab,
              labels: {
                StoreTab.products: l10n.storeTabProducts,
                StoreTab.about: l10n.storeTabAbout,
                StoreTab.policies: l10n.storeTabPolicies,
              },
              onSelect: _selectTab,
              background: Theme.of(context).scaffoldBackgroundColor,
              hairline: context.hairline,
            ),
          ),
          ...switch (tab) {
            StoreTab.products => _productSlivers(
              context,
              l10n,
              store,
              products,
            ),
            StoreTab.about => [
              SliverToBoxAdapter(
                child: StoreAboutTab(
                  profile: profile,
                  onPolicies: () => _selectTab(StoreTab.policies),
                  onCategory: _showCategory,
                ),
              ),
              _fillGrouped(context),
            ],
            StoreTab.policies => [
              SliverToBoxAdapter(child: StorePoliciesTab(profile: profile)),
              _fillGrouped(context),
            ],
          },
        ],
      ),
    );
  }

  /// Carries the About and Policies pages' grey down to the bottom.
  Widget _fillGrouped(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: ColoredBox(color: _groupedColor(context)),
  );

  Color _groupedColor(BuildContext context) =>
      context.isDarkMode ? AppColors.surfaceDark : AppColors.surfaceSubtle;

  /// The banner with the floating back, search and share buttons (Figma 13);
  /// scrolled, it collapses into a white bar titled with the store's name
  /// (13b).
  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    StoreProfile profile,
  ) {
    final store = profile.card;
    return SliverAppBar(
      pinned: true,
      expandedHeight: _headerHeight,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: false,
      leadingWidth: 64,
      leading: Center(
        child: _CircleButton(
          icon: Icons.arrow_back,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onTap: _back,
        ),
      ),
      titleSpacing: 0,
      title: AnimatedOpacity(
        opacity: _collapsed ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: Text(
          store.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            height: 24 / 18,
            fontWeight: FontWeight.w700,
            color: context.scaffoldHeading,
          ),
        ),
      ),
      actions: [
        _CircleButton(
          icon: Icons.search,
          tooltip: l10n.storeSearchHint(store.name),
          onTap: _focusSearch,
        ),
        if (store.webUrl != null) ...[
          const SizedBox(width: 8),
          _CircleButton(
            icon: Icons.share_outlined,
            tooltip: l10n.actionShare,
            onTap: () => _share(store),
          ),
        ],
        const SizedBox(width: 12),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _Banner(profile: profile, bannerHeight: _bannerHeight),
      ),
    );
  }

  List<Widget> _productSlivers(
    BuildContext context,
    AppLocalizations l10n,
    HmStoreCard store,
    PlpState state,
  ) {
    final products = _products;
    final searching = (products?.search ?? '').isNotEmpty;
    return [
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _StoreSearchField(
            controller: _search,
            focusNode: _searchFocus,
            hint: l10n.storeSearchHint(store.name),
            activeFilters: state.activeFilterCount,
            onChanged: _onSearchChanged,
            onSubmitted: _submitSearch,
            onClear: _clearSearch,
            onFilters: () => _openFilters(state),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _MetaRow(
          count: state.isLoading && state.products.isEmpty
              ? null
              : l10n.categoryProductCount(state.totalCount),
          sortLabel: switch (state.sort) {
            ProductSortField.relevance =>
              searching ? l10n.sortRelevance : l10n.sortFeatured,
            ProductSortField.priceAsc => l10n.sortPriceLowHigh,
            ProductSortField.priceDesc => l10n.sortPriceHighLow,
            ProductSortField.nameAsc => l10n.sortNameAz,
          },
          onSort: () => _openSort(state),
        ),
      ),
      ..._grid(context, l10n, state, searching: searching),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  List<Widget> _grid(
    BuildContext context,
    AppLocalizations l10n,
    PlpState state, {
    required bool searching,
  }) {
    if (state.isLoading && state.products.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: ProductGridSkeleton(
            childAspectRatio: 0.66,
            count: 4,
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
          ),
        ),
      ];
    }
    final error = state.error;
    if (error != null && state.products.isEmpty) {
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
                FilledButton(
                  onPressed: () => _products?.refresh(),
                  child: Text(l10n.actionRetry),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (state.products.isEmpty) {
      final filtered = searching || state.activeFilterCount > 0;
      return [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: filtered
                ? Icons.search_off_outlined
                : Icons.inventory_2_outlined,
            title: filtered ? l10n.storeNoMatches : l10n.storeNoProducts,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.66,
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
          child: ProductGridSkeleton(childAspectRatio: 0.66, count: 2),
        ),
    ];
  }
}

/// The banner photo (the brand navy without one) under a light scrim for the
/// buttons, and the logo overhanging its bottom edge.
class _Banner extends StatelessWidget {
  const _Banner({required this.profile, required this.bannerHeight});

  final StoreProfile profile;
  final double bannerHeight;

  @override
  Widget build(BuildContext context) {
    final url = profile.bannerUrl ?? '';
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: bannerHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isEmpty)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.topStart,
                      end: AlignmentDirectional.bottomEnd,
                      colors: [AppColors.brandPrimary, Color(0xFF1E3A6E)],
                    ),
                  ),
                )
              else
                HubImage(url: url, fit: BoxFit.cover, shimmer: true),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.45],
                    colors: [Color(0x73000000), Color(0x00000000)],
                  ),
                ),
              ),
            ],
          ),
        ),
        PositionedDirectional(
          start: 16,
          top: bannerHeight - 46,
          // Gone by half-way up, before it can reach the bar's buttons.
          child: Opacity(
            opacity: _logoOpacity(context),
            child: StoreLogo(
              store: profile.card,
              size: 80,
              borderWidth: 4,
              borderColor: Colors.white,
              shadow: true,
            ),
          ),
        ),
      ],
    );
  }
}

/// 1 with the header open, 0 from half-way collapsed.
double _logoOpacity(BuildContext context) {
  final settings = context
      .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
  if (settings == null || settings.maxExtent <= settings.minExtent) return 1;
  final open =
      (settings.currentExtent - settings.minExtent) /
      (settings.maxExtent - settings.minExtent);
  return ((open - 0.5) * 2).clamp(0.0, 1.0);
}

/// A white 40 pt round button over the banner; on the collapsed white bar it
/// reads as a plain icon button.
class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Colors.white,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: AppColors.inkHeading),
        ),
      ),
    ),
  );
}

/// The name with the verified mark, the seller's short description, and the
/// rating · products · joined figures (Figma 13 "store-info").
class _StoreInfo extends StatelessWidget {
  const _StoreInfo({required this.profile});

  final StoreProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = profile.card;
    final isEn = Localizations.localeOf(context).languageCode == 'en';
    final joined = store.joinedAt;
    final short = profile.shortDescription;
    final stats = <StoreStat>[
      if (store.isRated)
        StoreStat.rating(
          store.rating!,
          l10n.storeReviewCount(store.reviewCount),
        ),
      StoreStat(storeCount(store.productCount), l10n.storeStatProducts),
      if (joined != null)
        StoreStat('${joined.toLocal().year}', l10n.storeStatSellingSince),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StoreNameLine(
            name: store.name,
            markSize: 18,
            gap: 6,
            style: TextStyle(
              // Playfair Display has no Arabic glyphs.
              fontFamily: isEn ? AppTheme.displayFont : null,
              fontSize: 22,
              height: 28 / 22,
              fontWeight: FontWeight.w700,
              color: context.scaffoldHeading,
            ),
          ),
          if (short != null) ...[
            const SizedBox(height: 2),
            Text(
              short,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 16 / 12,
                color: context.scaffoldMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _HeaderStat(stat: stats[i])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.stat});

  final StoreStat stat;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    decoration: BoxDecoration(
      color: SearchStyle.pillFill(context),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        stat.valueText(
          TextStyle(
            fontSize: 16,
            height: 22 / 16,
            fontWeight: FontWeight.w600,
            color: context.scaffoldHeading,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            color: context.scaffoldMuted,
          ),
        ),
      ],
    ),
  );
}

/// The pinned tab row: start-aligned labels with the orange underline under
/// the chosen one, over a hairline.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({
    required this.tabs,
    required this.selected,
    required this.labels,
    required this.onSelect,
    required this.background,
    required this.hairline,
  });

  final List<StoreTab> tabs;
  final StoreTab selected;
  final Map<StoreTab, String> labels;
  final ValueChanged<StoreTab> onSelect;
  final Color background;
  final Color hairline;

  static const double _height = 45;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(bottom: BorderSide(color: hairline)),
      ),
      // Scrolls sideways rather than overflowing with large text.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              _TabLabel(
                label: labels[tabs[i]]!,
                selected: tabs[i] == selected,
                onTap: () => onSelect(tabs[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Cheap, and its callbacks change with every build of the page.
  @override
  bool shouldRebuild(covariant _TabsHeader old) => true;
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 12, bottom: 9),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.accent : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? context.scaffoldHeading : context.scaffoldMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Search MIA CO products", with the filter action inside the field — a dot
/// on it while filters are on.
class _StoreSearchField extends StatelessWidget {
  const _StoreSearchField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.activeFilters,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onFilters,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final int activeFilters;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = context.scaffoldMuted;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: TextStyle(
        fontSize: 14,
        height: 20 / 14,
        color: context.scaffoldHeading,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: TextStyle(fontSize: 14, height: 20 / 14, color: muted),
        filled: true,
        fillColor: SearchStyle.pillFill(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 11),
        prefixIcon: Icon(Icons.search, size: 18, color: muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: muted,
                tooltip: l10n.searchClearField,
                onPressed: onClear,
              ),
            IconButton(
              tooltip: activeFilters > 0
                  ? '${l10n.filtersLabel} ($activeFilters)'
                  : l10n.filtersLabel,
              onPressed: onFilters,
              icon: Badge(
                isLabelVisible: activeFilters > 0,
                smallSize: 8,
                backgroundColor: AppColors.accent,
                child: Icon(
                  Icons.tune,
                  size: 18,
                  color: context.scaffoldHeading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "38 products" and the sort action (⇅ Featured).
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.count,
    required this.sortLabel,
    required this.onSort,
  });

  /// Null while the first page loads.
  final String? count;
  final String sortLabel;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final color = context.scaffoldHeading;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 16 / 12,
                color: context.scaffoldMuted,
              ),
            ),
          ),
          InkWell(
            onTap: onSort,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_vert, size: 16, color: color),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      sortLabel,
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
          ),
        ],
      ),
    );
  }
}
