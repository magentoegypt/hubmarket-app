import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/brand.dart';
import '../brand_results_controller.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../search_controller.dart';
import '../search_history.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/sort_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';

/// Native catalogue search (`products(search:)`). If Live Search is later
/// confirmed (Open Q §4), swap the provider to the productSearch schema.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery, this.brand});

  /// Optional pre-filled query.
  final String? initialQuery;

  /// When set, this renders a brand landing: a brand image + name header (no
  /// search field), whose results are the brand's products.
  final Brand? brand;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  /// Submitted query — drives the results grid.
  String _query = '';

  /// Live (debounced) field text — drives the type-ahead suggestions.
  String _typed = '';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _controller.text = initial;
      _query = initial;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Debounce the suggestion query; refresh the clear (X) affordance now.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _typed = value.trim());
    });
    setState(() {});
  }

  void _submit(String term) {
    final t = term.trim();
    if (t.isEmpty) return;
    _debounce?.cancel();
    _controller.text = t;
    _controller.selection = TextSelection.collapsed(offset: t.length);
    ref.read(searchHistoryProvider.notifier).add(t);
    _focus.unfocus();
    setState(() {
      _query = t;
      _typed = '';
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
      _typed = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brand = widget.brand;
    // Brand landing: no search field; the brand header sits above the results.
    if (brand != null) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 4,
          toolbarHeight: 60,
          title: const BrandLogo(height: 44),
        ),
        body: _Results(query: brand.title, brand: brand),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const HubBackButton(),
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l10n.searchFieldHint,
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          onSubmitted: _submit,
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(icon: const Icon(Icons.close), onPressed: _clear),
        ],
      ),
      body: _query.isNotEmpty
          ? _Results(query: _query)
          : _typed.isNotEmpty
          ? _Suggestions(query: _typed, onPick: _submit)
          : _IdleState(onPick: _submit),
    );
  }
}

/// Type-ahead suggestions while typing (before submit): a "search this term"
/// action plus the top matching products (tap → PDP). Driven by the same
/// per-query search controller as the results grid (debounced upstream).
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.query, required this.onPick});
  final String query;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider(query));
    final products = state.products.take(6).toList();
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.search, color: AppColors.inkMuted),
          title: Text(l10n.searchForQuery(query)),
          onTap: () => onPick(query),
        ),
        if (state.isLoading && products.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
        for (final p in products)
          ListTile(
            leading: HubImage(
              url: p.thumbnail,
              width: 44,
              height: 44,
              borderRadius: BorderRadius.circular(8),
              error: (_) => const ColoredBox(color: AppColors.surfaceTint),
            ),
            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => openProduct(context, p),
          ),
      ],
    );
  }
}

/// Idle search screen (no query yet): persisted recent searches + trending
/// chips, both tap-to-search.
class _IdleState extends ConsumerWidget {
  const _IdleState({required this.onPick});
  final ValueChanged<String> onPick;

  static const _sectionStyle = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 15,
    color: AppColors.inkHeading,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(searchHistoryProvider);
    final trending = l10n.searchTrendingCsv
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (history.isNotEmpty) ...[
          Row(
            children: [
              Expanded(
                child: Text(l10n.searchRecentTitle, style: _sectionStyle),
              ),
              TextButton(
                onPressed: () =>
                    ref.read(searchHistoryProvider.notifier).clear(),
                child: Text(l10n.searchClearHistory),
              ),
            ],
          ),
          for (final term in history)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.history, color: AppColors.inkMuted),
              title: Text(term),
              trailing: const Icon(
                Icons.north_west,
                size: 16,
                color: AppColors.inkMuted,
              ),
              onTap: () => onPick(term),
            ),
          const SizedBox(height: 20),
        ],
        Text(l10n.searchTrendingTitle, style: _sectionStyle),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final term in trending)
              ActionChip(label: Text(term), onPressed: () => onPick(term)),
          ],
        ),
      ],
    );
  }
}

/// Search results grid with a "Search results for …" header and the shared
/// aggregation-driven Filters + Sort sheet (same engine as the PLP).
class _Results extends ConsumerStatefulWidget {
  const _Results({required this.query, this.brand});
  final String query;
  final Brand? brand;

  @override
  ConsumerState<_Results> createState() => _ResultsState();
}

class _ResultsState extends ConsumerState<_Results> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _Results old) {
    super.didUpdateWidget(old);
    // New query → jump back to the top of the (now different) result set.
    if (old.query != widget.query && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A brand landing (brand with a linked manufacturer option) lists that
  /// brand's products via the [BrandResultsController]; a plain query uses the
  /// [SearchResultsController]. Both expose the same PlpState + action surface.
  bool get _isBrand => widget.brand?.optionId != null;
  int get _brandId => widget.brand!.optionId!;

  PlpState _watchState() => _isBrand
      ? ref.watch(brandResultsControllerProvider(_brandId))
      : ref.watch(searchControllerProvider(widget.query));

  void _loadMore() => _isBrand
      ? ref.read(brandResultsControllerProvider(_brandId).notifier).loadMore()
      : ref.read(searchControllerProvider(widget.query).notifier).loadMore();

  Future<void> _refresh() => _isBrand
      ? ref.read(brandResultsControllerProvider(_brandId).notifier).refresh()
      : ref.read(searchControllerProvider(widget.query).notifier).refresh();

  void _applyResult(FilterResult result) {
    if (_isBrand) {
      ref
          .read(brandResultsControllerProvider(_brandId).notifier)
          .applyFilters(
            result.attributes,
            priceFrom: result.priceFrom,
            priceTo: result.priceTo,
            minDiscount: result.minDiscount,
            minRating: result.minRating,
          );
    } else {
      ref
          .read(searchControllerProvider(widget.query).notifier)
          .applyFilters(
            result.attributes,
            priceFrom: result.priceFrom,
            priceTo: result.priceTo,
            minDiscount: result.minDiscount,
            minRating: result.minRating,
          );
    }
  }

  void _setSort(ProductSortField sort) => _isBrand
      ? ref.read(brandResultsControllerProvider(_brandId).notifier).setSort(sort)
      : ref.read(searchControllerProvider(widget.query).notifier).setSort(sort);

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      _loadMore();
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
    if (result != null) _applyResult(result);
  }

  /// Dedicated Sort control (QA wants filter + sort as separate lists) — the
  /// shared [SortSheet], labelled "Relevance" for search results.
  Future<void> _openSort(PlpState state) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showModalBottomSheet<ProductSortField>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) =>
          SortSheet(current: state.sort, relevanceLabel: l10n.sortRelevance),
    );
    if (selected != null) _setSort(selected);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = _watchState();

    if (state.isLoading && state.products.isEmpty) {
      return ListView(
        children: [
          _Header(
            query: widget.query,
            state: state,
            onFilters: () => _openFilters(state),
            onSort: () => _openSort(state),
            brand: widget.brand,
          ),
          const ProductGridSkeleton(childAspectRatio: 0.58, count: 6),
        ],
      );
    }

    if (state.error != null && state.products.isEmpty) {
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
                onPressed: _refresh,
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
            query: widget.query,
            state: state,
            onFilters: () => _openFilters(state),
            onSort: () => _openSort(state),
            brand: widget.brand,
          ),
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
            padding: const EdgeInsets.all(16),
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
}

/// "Search results for …" title + the result count and the Filters/Sort pill.
class _Header extends StatelessWidget {
  const _Header({
    required this.query,
    required this.state,
    required this.onFilters,
    required this.onSort,
    this.brand,
  });

  final String query;
  final PlpState state;
  final VoidCallback onFilters;
  final VoidCallback onSort;
  final Brand? brand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final b = brand;
    final filtersLabel = state.activeFilterCount > 0
        ? '${l10n.filtersLabel} (${state.activeFilterCount})'
        : l10n.filtersLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (b != null)
          // Brand landing header: logo + name above the product count.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
            child: Column(
              children: [
                if (b.imageUrl.isNotEmpty) ...[
                  HubImage(
                    url: b.imageUrl,
                    height: 60,
                    fit: BoxFit.contain,
                    placeholder: (_) => const SizedBox.shrink(),
                    error: (_) => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  b.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
            child: Text(
              l10n.searchResultsFor(query),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
          child: Row(
            children: [
              Text(
                l10n.resultsCount(state.totalCount),
                style: TextStyle(
                  color: context.scaffoldMuted,
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              _PillButton(
                icon: Icons.swap_vert,
                label: l10n.sortLabel,
                onTap: onSort,
              ),
              const SizedBox(width: 8),
              _PillButton(
                icon: Icons.tune,
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

/// Bordered Filters/Sort pill (mirrors the PLP header control).
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
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.hairline),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // White in dark mode — the pill sits on the scaffold (QA).
          Icon(icon, size: 16, color: context.scaffoldHeading),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.scaffoldHeading),
          ),
        ],
      ),
    ),
  );
}
