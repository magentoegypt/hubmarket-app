import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/brand.dart';
import '../../domain/category.dart';
import '../brand_results_controller.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../search_controller.dart';
import '../search_history.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';
import '../widgets/search_field_bar.dart';
import '../widgets/search_landing.dart';
import '../widgets/search_results_view.dart';
import '../widgets/search_type_ahead.dart';
import '../widgets/sort_sheet.dart';

/// Which of the search designs is on screen.
enum _SearchMode {
  /// Nothing typed (Figma 09b).
  landing,

  /// Typing, with live suggestions (Figma 09).
  typeAhead,

  /// A submitted search's full results (Figma 09c).
  results,
}

/// Catalogue search (QA01, "search behaves like the website"). The field drives
/// three states — landing, type-ahead and results — and a search with no
/// results shows the S2 page in either of the last two. Every result comes from
/// `products(search:)`, which Hub Market answers through Algolia, the same
/// engine and ranking as the website's search.
///
/// With [brand] set this is instead a brand landing: the brand's image + name
/// over its products, with no search field.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery, this.brand});

  /// Opens straight onto the results for this query.
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

  /// Suggestions wait this long after the last keystroke.
  static const Duration _debounceDelay = Duration(milliseconds: 250);

  /// The submitted query — what the results page shows. Empty until a search
  /// is submitted.
  String _query = '';

  /// The field's text once typing pauses — what the type-ahead searches.
  String _typed = '';

  /// True while the field is being edited. Kept apart from focus, so hiding
  /// the keyboard with a scroll doesn't swap the type-ahead for the results.
  bool _editing = true;

  /// The top-level category the search is narrowed to; null for all.
  Category? _scope;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialQuery?.trim() ?? '';
    if (initial.isNotEmpty) {
      _setText(initial);
      _query = initial;
      _typed = initial;
      _editing = false;
    }
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _focus.removeListener(_onFocusChange);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  _SearchMode get _mode {
    if (_query.isNotEmpty && !_editing) return _SearchMode.results;
    if (_controller.text.trim().isEmpty) return _SearchMode.landing;
    return _SearchMode.typeAhead;
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Tapping into the field on the results page goes back to editing, starting
  /// from the suggestions for what is already there.
  void _onFocusChange() {
    if (!_focus.hasFocus || _editing) return;
    setState(() {
      _editing = true;
      _typed = _controller.text.trim();
    });
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final text = value.trim();
    if (text.isEmpty) {
      setState(() => _typed = '');
      return;
    }
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _typed = text);
    });
    // Landing → type-ahead switches on the first character.
    setState(() {});
  }

  void _submit(String term) {
    final text = term.trim();
    if (text.isEmpty) return;
    _debounce?.cancel();
    _setText(text);
    ref.read(searchHistoryProvider.notifier).add(text);
    _focus.unfocus();
    setState(() {
      _query = text;
      _typed = text;
      _editing = false;
    });
  }

  void _clearField() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _typed = '';
      _editing = true;
    });
    _focus.requestFocus();
  }

  /// Cancel leaves search — unless the field is being edited over results,
  /// which it then returns to unchanged.
  void _cancel() {
    if (_query.isEmpty) {
      Navigator.maybePop(context);
      return;
    }
    _debounce?.cancel();
    _setText(_query);
    _focus.unfocus();
    setState(() {
      _typed = _query;
      _editing = false;
    });
  }

  Future<void> _pickScope() async {
    final picked = await showModalBottomSheet<SearchScopePick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SearchScopeSheet(selectedUid: _scope?.uid),
    );
    if (picked == null || !mounted) return;
    setState(() => _scope = picked.category);
  }

  @override
  Widget build(BuildContext context) {
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

    final mode = _mode;
    final initial = widget.initialQuery?.trim() ?? '';
    return HubScaffold(
      currentTab: AppTab.categories,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 0,
        toolbarHeight: SearchFieldBar.height,
        scrolledUnderElevation: 0,
        title: SearchFieldBar(
          controller: _controller,
          focusNode: _focus,
          autofocus: initial.isEmpty,
          emphasised: mode != _SearchMode.results,
          onBack: mode == _SearchMode.results
              ? () => Navigator.maybePop(context)
              : null,
          onCancel: mode == _SearchMode.results ? null : _cancel,
          onChanged: _onChanged,
          onSubmitted: _submit,
          onClear: _clearField,
        ),
      ),
      body: switch (mode) {
        _SearchMode.landing => SearchLanding(onPick: _submit),
        _SearchMode.typeAhead => SearchTypeAhead(
          query: _typed,
          scope: _scope,
          onScopeTap: _pickScope,
          onViewAll: () => _submit(_controller.text),
        ),
        _SearchMode.results => SearchResultsView(
          request: SearchRequest(_query, categoryUid: _scope?.uid),
          scopeName: _scope?.name,
        ),
      },
    );
  }
}

/// A brand landing's product grid under the brand header, with the shared
/// aggregation-driven Filters + Sort sheets (same engine as the PLP).
class _Results extends ConsumerStatefulWidget {
  const _Results({required this.query, required this.brand});
  final String query;
  final Brand brand;

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

  /// A brand with a linked manufacturer option lists that brand's products via
  /// the [BrandResultsController]; one without falls back to a search for its
  /// name ([SearchResultsController]). Both expose the same PlpState + action
  /// surface.
  bool get _isBrand => widget.brand.optionId != null;
  int get _brandId => widget.brand.optionId!;
  SearchRequest get _search => SearchRequest(widget.query);

  PlpState _watchState() => _isBrand
      ? ref.watch(brandResultsControllerProvider(_brandId))
      : ref.watch(searchControllerProvider(_search));

  void _loadMore() => _isBrand
      ? ref.read(brandResultsControllerProvider(_brandId).notifier).loadMore()
      : ref.read(searchControllerProvider(_search).notifier).loadMore();

  Future<void> _refresh() => _isBrand
      ? ref.read(brandResultsControllerProvider(_brandId).notifier).refresh()
      : ref.read(searchControllerProvider(_search).notifier).refresh();

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
          .read(searchControllerProvider(_search).notifier)
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
      ? ref
            .read(brandResultsControllerProvider(_brandId).notifier)
            .setSort(sort)
      : ref.read(searchControllerProvider(_search).notifier).setSort(sort);

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
              FilledButton(onPressed: _refresh, child: Text(l10n.actionRetry)),
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

/// The brand's logo + name, then the result count and the Filters/Sort pills.
class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.onFilters,
    required this.onSort,
    required this.brand,
  });

  final PlpState state;
  final VoidCallback onFilters;
  final VoidCallback onSort;
  final Brand brand;

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
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
          child: Column(
            children: [
              if (brand.imageUrl.isNotEmpty) ...[
                HubImage(
                  url: brand.imageUrl,
                  height: 60,
                  fit: BoxFit.contain,
                  placeholder: (_) => const SizedBox.shrink(),
                  error: (_) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                brand.title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
          child: Row(
            children: [
              Text(
                l10n.resultsCount(state.totalCount),
                style: TextStyle(color: context.scaffoldMuted, fontSize: 12.5),
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
