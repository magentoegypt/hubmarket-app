import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
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
import '../../../deals/presentation/widgets/star_glyph.dart';
import '../../domain/store.dart';
import '../store_products_controller.dart';
import '../store_reviews_controller.dart';
import '../stores_providers.dart';
import '../widgets/store_about.dart';
import '../widgets/store_reviews.dart';
import '../widgets/store_widgets.dart';
import '../widgets/stores_unavailable.dart';

/// The tabs of a store page, in order.
enum StoreTab { products, reviews, about, policies }

/// One seller's store (Figma 13, and 13b for its About tab): the banner with
/// the logo, name, location and figures, "Contact vendor", then Products (the
/// seller's catalogue with the PLP's search, filters, sort and paging),
/// Reviews, About and Policies.
///
/// Products is the store's front page (13): a banner under the status bar with
/// floating back / search / share buttons, the logo overhanging it, and the
/// figures, which collapse into a bar titled with the store's name as the page
/// scrolls. The other tabs are its inside pages (13b): the bar always shows
/// the store's name, a compact row (logo, name, where and since when, the
/// rating) sits under it, and the four equal tabs pin below that.
///
/// From `hmStore(code)`; the products are core `products` filtered by the
/// seller's `vendor_id`. A card handed over by the list ([preview]) paints the
/// header and starts the products at once.
///
/// The Reviews tab (`hmStoreReviews`), "Contact vendor" and "Call" (the
/// telephone the website's store page dials), the location line, the
/// category and the Sales figure need the server to list the `vendors`
/// capability ([storeExtrasProvider]); without it the page is the P3 one.
/// There is no favourite: neither the website nor Vnecoms lets a shopper
/// follow a store. Policies shows only when the seller publishes one.
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
  Timer? _debounce;

  StoreTab _tab = StoreTab.products;
  bool _collapsed = false;

  /// The seller whose products are listed, once known.
  int? _vendorId;

  /// The banner, which includes the status bar's area (Figma 13), and the
  /// header with the white strip the logo overhangs into.
  static const double _bannerHeight = 196;
  static const double _headerHeight = 236;

  /// The floating buttons sit 5 px under the status bar: 40 px in a 50 px bar.
  static const double _toolbarHeight = 50;

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

  /// The seller's code as the backend spells it, once known (keys the
  /// Reviews tab).
  String? _sellerCode;

  StoreProductsController? get _products => _vendorId == null
      ? null
      : ref.read(storeProductsControllerProvider(_vendorId!).notifier);

  /// The status bar's height, read from the view: the page's zero-size scaffold
  /// app bar hides it from the body's MediaQuery.
  double get _statusBar {
    final view = View.of(context);
    return view.padding.top / view.devicePixelRatio;
  }

  /// How far the front page scrolls before its header is the collapsed bar.
  double get _collapseDistance => _headerHeight - _toolbarHeight - _statusBar;

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final collapsed = _scroll.offset > _collapseDistance - 12;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    if (_scroll.position.pixels < _scroll.position.maxScrollExtent - 400) {
      return;
    }
    if (_tab == StoreTab.products) _products?.loadMore();
  }

  /// The inside pages page their reviews as they scroll.
  bool _onInnerScroll(ScrollNotification notification) {
    if (_tab == StoreTab.reviews &&
        _sellerCode != null &&
        notification.metrics.axis == Axis.vertical &&
        notification.metrics.extentAfter < 400) {
      ref
          .read(storeReviewsControllerProvider(_sellerCode!).notifier)
          .loadMore();
    }
    return false;
  }

  /// Dials the seller (the website's "Contact Vendor" is a `tel:` link).
  Future<void> _call(Uri phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final opened = await ref.read(externalUriLauncherProvider)(phone);
    if (!opened && mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  void _selectTab(StoreTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _collapsed = false;
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
    final picked = await showHubBottomSheet<ProductSortField>(
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
          icon: HubIcons.store,
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
    _sellerCode = profile.card.code;
    return _page(context, l10n, profile);
  }

  /// A state without the store (loading, missing, failed): the scaffold with
  /// a back button over [body].
  Widget _plain(BuildContext context, Widget body) => HubScaffold(
    currentTab: AppTab.home,
    appBar: HubTopBar(showBack: true, onBack: _back),
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
    final extras = ref.watch(storeExtrasProvider);
    final phone = extras ? profile.phoneUri : null;
    final tabs = [
      StoreTab.products,
      if (extras) StoreTab.reviews,
      StoreTab.about,
      if (profile.hasPolicies) StoreTab.policies,
    ];
    final tab = tabs.contains(_tab) ? _tab : StoreTab.products;
    final labels = {
      StoreTab.products: l10n.storeTabProducts,
      StoreTab.reviews: l10n.storeTabReviews,
      StoreTab.about: l10n.storeTabAbout,
      StoreTab.policies: l10n.storeTabPolicies,
    };
    final labelStyle = AppTextStyles.of(context).body;
    final tabLine =
        MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) *
        labelStyle.height!;

    if (tab != StoreTab.products) {
      // The inside pages (Figma 13b).
      return HubScaffold(
        currentTab: AppTab.home,
        appBar: HubTopBar(
          title: store.name,
          showBack: true,
          onBack: _back,
          actions: [
            HubIconButton(
              icon: HubIcons.search,
              tooltip: l10n.storeSearchHint(store.name),
              onPressed: _focusSearch,
            ),
            if (store.webUrl != null) ...[
              const SizedBox(width: 4), // the frames' 4 px between items
              HubIconButton(
                icon: HubIcons.share2,
                tooltip: l10n.actionShare,
                onPressed: () => _share(store),
              ),
            ],
          ],
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: _onInnerScroll,
          child: CustomScrollView(
            // Each tab opens at its top.
            key: ValueKey(tab),
            slivers: [
              SliverToBoxAdapter(
                child: _StoreRow(profile: profile, extras: extras),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(
                  tabs: tabs,
                  selected: tab,
                  labels: labels,
                  onSelect: _selectTab,
                  lineHeight: tabLine,
                  compact: true,
                ),
              ),
              ...switch (tab) {
                StoreTab.reviews => [
                  ...storeReviewsSlivers(
                    context,
                    ref.watch(storeReviewsControllerProvider(store.code)),
                    onRetry: () => ref
                        .read(
                          storeReviewsControllerProvider(store.code).notifier,
                        )
                        .refresh(),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
                StoreTab.about => [
                  SliverToBoxAdapter(
                    child: StoreAboutTab(
                      profile: profile,
                      onPolicies: () => _selectTab(StoreTab.policies),
                      onCategory: _showCategory,
                      salesCount: extras ? profile.salesCount : null,
                      onCall: phone == null ? null : () => _call(phone),
                    ),
                  ),
                  _fillGrouped(context),
                ],
                _ => [
                  SliverToBoxAdapter(child: StorePoliciesTab(profile: profile)),
                  _fillGrouped(context),
                ],
              },
            ],
          ),
        ),
      );
    }

    // The front page (Figma 13): the header is the scroll view's own
    // collapsing bar.
    return HubScaffold(
      currentTab: AppTab.home,
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
            child: _StoreInfo(
              profile: profile,
              extras: extras,
              onContact: phone == null ? null : () => _call(phone),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              tabs: tabs,
              selected: tab,
              labels: labels,
              onSelect: _selectTab,
              lineHeight: tabLine,
            ),
          ),
          ..._productSlivers(context, l10n, store, products),
        ],
      ),
    );
  }

  /// Carries the About and Policies pages' grey down to the bottom.
  Widget _fillGrouped(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: ColoredBox(color: groupedPageColor(context)),
  );

  /// The banner with the floating back, search and share buttons (Figma 13);
  /// scrolled, it collapses into a white bar titled with the store's name.
  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    StoreProfile profile,
  ) {
    final store = profile.card;
    // The scaffold's zero-size app bar (see [_page]) makes it hide the status
    // bar inset from the body, so a SliverAppBar would put its toolbar — the
    // back, search and share buttons — under the clock on a phone that draws
    // edge-to-edge (Android 15+). The real inset is read from the view. It
    // adds to the expanded and the collapsed height alike, so the header's
    // expanded height below is what Figma draws, status bar included.
    final media = MediaQuery.of(context);
    final inset = _statusBar;
    return MediaQuery(
      data: media.copyWith(padding: media.padding.copyWith(top: inset)),
      child: _headerBar(context, l10n, store, profile, inset),
    );
  }

  Widget _headerBar(
    BuildContext context,
    AppLocalizations l10n,
    HmStoreCard store,
    StoreProfile profile,
    double inset,
  ) {
    final t = AppTextStyles.of(context);
    return SliverAppBar(
      pinned: true,
      expandedHeight: _headerHeight - inset,
      toolbarHeight: _toolbarHeight,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: false,
      // The back button is 16 px from the edge: 40 px in 72.
      leadingWidth: 72,
      leading: Center(
        child: HubIconButton(
          icon: HubIcons.arrowLeft,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          background: Colors.white,
          onPressed: _back,
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
          style: t.heading2.copyWith(color: context.scaffoldHeading),
        ),
      ),
      actions: [
        HubIconButton(
          icon: HubIcons.search,
          tooltip: l10n.storeSearchHint(store.name),
          background: Colors.white,
          onPressed: _focusSearch,
        ),
        if (store.webUrl != null) ...[
          const SizedBox(width: 8),
          HubIconButton(
            icon: HubIcons.share2,
            tooltip: l10n.actionShare,
            background: Colors.white,
            onPressed: () => _share(store),
          ),
        ],
        const SizedBox(width: 16),
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
          child: StoreSearchField(
            height: 42,
            controller: _search,
            focusNode: _searchFocus,
            hint: l10n.storeSearchHint(store.name),
            onChanged: _onSearchChanged,
            onSubmitted: _submitSearch,
            onClear: _clearSearch,
            // The filter action 14 px from the end: a 40 px button, 3 px short.
            trailing: Padding(
              padding: const EdgeInsetsDirectional.only(end: 3),
              child: HubIconButton(
                icon: HubIcons.slidersHorizontal,
                iconSize: 18,
                showDot: state.activeFilterCount > 0,
                tooltip: state.activeFilterCount > 0
                    ? '${l10n.filtersLabel} (${state.activeFilterCount})'
                    : l10n.filtersLabel,
                onPressed: () => _openFilters(state),
              ),
            ),
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
            icon: filtered ? HubIcons.searchX : HubIcons.package,
            title: filtered ? l10n.storeNoMatches : l10n.storeNoProducts,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 0),
        sliver: SliverGrid(
          // Figma 13's cards: 16 px apart across, 14 down.
          gridDelegate: ProductGridDelegate(
            infoHeight: ProductCardMetrics.infoHeight(context),
            mainAxisSpacing: 14,
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

/// The name with the verified mark, the location line ("Dubai, United Arab
/// Emirates · Furniture"), the rating · products · joined figures and "Contact
/// vendor" (Figma 13 "store-info").
class _StoreInfo extends StatelessWidget {
  const _StoreInfo({
    required this.profile,
    this.extras = false,
    this.onContact,
  });

  final StoreProfile profile;

  /// The P3.1 fields may show (the location line and its category).
  final bool extras;

  /// Dials the seller; null hides "Contact vendor" (no number published).
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final store = profile.card;
    final joined = store.joinedAt;
    final place = extras
        ? [?profile.location, ?store.categoryName].join(' · ')
        : '';
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
            // EN/Heading 1: Playfair Display (Arabic: Tajawal).
            style: t.heading1.copyWith(color: context.scaffoldHeading),
          ),
          if (place.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(HubIcons.mapPin, size: 14, color: context.scaffoldMuted),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    place,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: context.scaffoldMuted),
                  ),
                ),
              ],
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
          if (onContact != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 52,
              // The theme's FilledButton is Figma's Button.
              child: FilledButton.icon(
                onPressed: onContact,
                icon: const Icon(HubIcons.phone, size: 20),
                label: Text(l10n.storeContactVendor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.stat});

  final StoreStat stat;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: SearchStyle.pillFill(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          stat.valueText(t.title.copyWith(color: context.scaffoldHeading)),
          const SizedBox(height: 2),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.caption.copyWith(color: context.scaffoldMuted),
          ),
        ],
      ),
    );
  }
}

/// The inside pages' store row (Figma 13b "store-row"): the 52 px logo, the
/// name with its verified mark, where the seller is and since when it sells,
/// and its rating in a green-tinted pill.
class _StoreRow extends StatelessWidget {
  const _StoreRow({required this.profile, required this.extras});

  final StoreProfile profile;
  final bool extras;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final store = profile.card;
    final joined = store.joinedAt;
    final caption = [
      if (extras) ?profile.location,
      if (joined != null)
        '${AppLocalizations.of(context).storeStatSellingSince} '
            '${storeJoinedShort(context, joined.toLocal())}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
      child: Row(
        children: [
          StoreLogo(store: store, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StoreNameLine(
                  name: store.name,
                  markSize: 14,
                  style: t.title.copyWith(color: context.scaffoldHeading),
                ),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.copyWith(color: context.scaffoldMuted),
                  ),
                ],
              ],
            ),
          ),
          if (store.isRated) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.successSubtle,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StarGlyph(),
                  const SizedBox(width: 4),
                  Text(
                    formatStoreRating(store.rating!),
                    style: t.captionStrong.copyWith(
                      color: AppColors.inkHeading,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The pinned tab row, in the two looks Figma draws. The front page's (13):
/// start-aligned labels 20 apart, the orange 3 px underline under the chosen
/// one's label, over a hairline. The inside pages' (13b): four equal columns
/// with centred labels, the underline 2 px across the chosen column.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  const _TabsHeader({
    required this.tabs,
    required this.selected,
    required this.labels,
    required this.onSelect,
    required this.lineHeight,
    this.compact = false,
  });

  final List<StoreTab> tabs;
  final StoreTab selected;
  final Map<StoreTab, String> labels;
  final ValueChanged<StoreTab> onSelect;

  /// The label's line (Body: 20 px, 22 in Arabic, at 1x text).
  final double lineHeight;
  final bool compact;

  /// The line with 12 above and 10 below, the 3 px underline and the hairline
  /// (13: 46 px); with 12 above and below, the 2 px underline and the hairline
  /// (13b: 47 px).
  double get _height => compact ? lineHeight + 27 : lineHeight + 26;

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
    final background = Theme.of(context).scaffoldBackgroundColor;
    final rule = BoxDecoration(
      color: background,
      border: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
    );
    if (compact) {
      return Container(
        decoration: rule,
        child: Row(
          children: [
            for (final tab in tabs)
              Expanded(
                child: _CompactTab(
                  label: labels[tab]!,
                  selected: tab == selected,
                  onTap: () => onSelect(tab),
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      decoration: rule,
      // Scrolls sideways rather than overflowing with large text.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: 20),
              _FrontTab(
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

/// A front-page tab (Figma 13): 12 above and 10 below the label, the chosen
/// one in Body Strong ink with a 3 px accent underline, the others in Body
/// muted — which, being 3 px shorter, sit 1.5 px lower, as the frame has them.
class _FrontTab extends StatelessWidget {
  const _FrontTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.only(top: 12, bottom: 10),
          decoration: BoxDecoration(
            border: selected
                ? const Border(
                    bottom: BorderSide(color: AppColors.accent, width: 3),
                  )
                : null,
          ),
          child: Text(
            label,
            style: selected
                ? t.bodyStrong.copyWith(color: context.scaffoldHeading)
                : t.body.copyWith(color: context.scaffoldMuted),
          ),
        ),
      ),
    );
  }
}

/// An inside-page tab (Figma 13b): a quarter of the width, the label centred
/// 12 px from the top and bottom, the chosen one in Body Strong ink with a
/// 2 px accent underline across the column.
class _CompactTab extends StatelessWidget {
  const _CompactTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              border: selected
                  ? const Border(
                      bottom: BorderSide(color: AppColors.accent, width: 2),
                    )
                  : null,
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: selected
                  ? t.bodyStrong.copyWith(color: context.scaffoldHeading)
                  : t.body.copyWith(color: context.scaffoldMuted),
            ),
          ),
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
    final t = AppTextStyles.of(context);
    final color = context.scaffoldHeading;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: context.scaffoldMuted),
            ),
          ),
          InkWell(
            onTap: onSort,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(4, 11, 0, 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(HubIcons.arrowUpDown, size: 16, color: color),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      sortLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.captionStrong.copyWith(color: color),
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
