import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/category.dart';
import '../../domain/product.dart';
import '../../domain/search_facets.dart';
import '../../domain/search_highlight.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../search_controller.dart';
import '../search_providers.dart';
import 'search_no_results.dart';
import 'search_style.dart';

/// The type-ahead while a search is being typed (Figma 09): a category scope,
/// the top products with the typed words highlighted, the "See products in …"
/// line, and a bar pinned above the keyboard with the result's top categories,
/// "View all N results" and the Algolia attribution.
///
/// The frame's "Pages" chips are left out: GraphQL has no CMS page search, so
/// they wait for Build 2.
class SearchTypeAhead extends ConsumerStatefulWidget {
  const SearchTypeAhead({
    super.key,
    required this.query,
    required this.scope,
    required this.onScopeTap,
    required this.onViewAll,
  });

  /// The debounced text — empty while the first keystrokes settle.
  final String query;

  /// The top-level category the search is narrowed to; null for all.
  final Category? scope;
  final VoidCallback onScopeTap;

  /// Opens the full results (Figma 09c).
  final VoidCallback onViewAll;

  /// Product rows shown.
  static const int hitLimit = 5;

  /// Categories linked in the "See products in … or in A, B" line.
  static const int linkLimit = 2;

  /// Chips in the pinned Categories row.
  static const int chipLimit = 5;

  @override
  ConsumerState<SearchTypeAhead> createState() => _SearchTypeAheadState();
}

class _SearchTypeAheadState extends ConsumerState<SearchTypeAhead> {
  /// The last answer that finished loading. While the next keystroke's search
  /// is in flight the type-ahead keeps showing it, under a progress bar, rather
  /// than blanking — the backend takes a few seconds a request.
  _Answer? _last;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scopeChip = _ScopeChip(
      label: widget.scope?.name ?? l10n.searchAllCategories,
      onTap: widget.onScopeTap,
    );
    final query = widget.query.trim();
    if (query.isEmpty) {
      return Column(children: [const _Pending(), scopeChip]);
    }

    final request = SearchRequest(query, categoryUid: widget.scope?.uid);
    final state = ref.watch(searchControllerProvider(request));
    final categories = ref.watch(searchResultCategoriesProvider(request));

    if (!state.isLoading && state.error == null) {
      _last = _Answer(request, state, categories);
    }
    final previous = _last;
    final answer = !state.isLoading
        ? _Answer(request, state, categories)
        : (previous != null &&
                  previous.request.categoryUid == request.categoryUid
              ? previous
              : null);

    if (answer == null || (state.error != null && state.products.isEmpty)) {
      final error = state.error;
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (error == null) const _Pending() else const SizedBox(height: 6),
          scopeChip,
          if (error != null)
            _ErrorRow(
              message: error is Failure
                  ? failureMessage(context, error)
                  : l10n.errorGeneric,
              onRetry: () => ref
                  .read(searchControllerProvider(request).notifier)
                  .refresh(),
            ),
        ],
      );
    }

    if (answer.state.products.isEmpty) {
      return Column(
        children: [
          if (state.isLoading) const _Pending() else const SizedBox(height: 6),
          if (widget.scope != null) scopeChip,
          Expanded(child: SearchNoResults(query: answer.request.query)),
        ],
      );
    }

    final total = answer.state.totalCount;
    return Column(
      children: [
        if (state.isLoading) const _Pending() else const SizedBox(height: 6),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              scopeChip,
              _GroupLabel(text: l10n.searchProductsHeading.toUpperCase()),
              const SizedBox(height: 4),
              for (final product in answer.state.products.take(
                SearchTypeAhead.hitLimit,
              ))
                _HitRow(product: product, query: answer.request.query),
              _SeeProductsIn(
                allLabel: widget.scope?.name ?? l10n.searchAllDepartments,
                total: total,
                categories: answer.categories
                    .take(SearchTypeAhead.linkLimit)
                    .toList(growable: false),
                onAll: widget.onViewAll,
              ),
            ],
          ),
        ),
        _PinnedActions(
          total: total,
          categories: answer.categories
              .take(SearchTypeAhead.chipLimit)
              .toList(growable: false),
          onViewAll: widget.onViewAll,
        ),
      ],
    );
  }
}

/// One finished search, as the type-ahead draws it.
class _Answer {
  const _Answer(this.request, this.state, this.categories);

  final SearchRequest request;
  final PlpState state;
  final List<SearchCategory> categories;
}

/// Opens a category's listing — what every category link in search does.
void openSearchCategory(BuildContext context, String uid, String name) =>
    context.push(AppRoutes.category(uid), extra: name);

/// A 2 pt progress bar in the 6 pt gap under the field while a search loads.
class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 6,
    child: Align(
      alignment: Alignment.topCenter,
      child: LinearProgressIndicator(
        minHeight: 2,
        color: AppColors.accent,
        backgroundColor: Colors.transparent,
      ),
    ),
  );
}

/// "All categories ▾" — narrows the search to one top-level category.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(side: BorderSide(color: context.hairline));
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Material(
          color: context.isDarkMode ? Colors.transparent : Colors.white,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 10, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w600,
                        color: context.scaffoldHeading,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 14,
                    color: context.scaffoldHeading,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "PRODUCTS" above the hits.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
          color: context.scaffoldMuted,
        ),
      ),
    );
  }
}

/// One product hit: 48 pt thumbnail · name with the typed words in bold
/// orange over "in Home Furniture" · price, with the regular price struck
/// through when discounted. Opens the PDP.
class _HitRow extends StatelessWidget {
  const _HitRow({required this.product, required this.query});

  final Product product;
  final String query;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final category = product.primaryCategory;
    return InkWell(
      onTap: () => openProduct(context, product),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            HubImage(
              url: product.thumbnail,
              width: 48,
              height: 48,
              borderRadius: BorderRadius.circular(8),
              error: (_) => const ColoredBox(color: AppColors.surfaceTint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SearchHighlightedText(text: product.name, query: query),
                  if (category != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      l10n.searchInCategory(category.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: context.scaffoldMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            _HitPrice(product: product),
          ],
        ),
      ),
    );
  }
}

/// A product name with the words of [query] drawn bold in the accent colour.
class SearchHighlightedText extends StatelessWidget {
  const SearchHighlightedText({
    super.key,
    required this.text,
    required this.query,
  });

  final String text;
  final String query;

  /// The style of the matched words.
  static const TextStyle matchStyle = TextStyle(
    fontWeight: FontWeight.w700,
    color: AppColors.accentStrong,
  );

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    var at = 0;
    for (final slice in searchMatchSlices(text, query)) {
      if (slice.start > at) {
        spans.add(TextSpan(text: text.substring(at, slice.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(slice.start, slice.end),
          style: matchStyle,
        ),
      );
      at = slice.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 14,
        height: 20 / 14,
        color: context.scaffoldHeading,
      ),
    );
  }
}

class _HitPrice extends StatelessWidget {
  const _HitPrice({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final regular = product.regularPrice;
    final effective = product.finalPrice ?? regular;
    if (effective == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          effective.formatted(),
          // Keep "AED 1,234.00" left-to-right inside an RTL row.
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w700,
            color: context.scaffoldHeading,
          ),
        ),
        if (product.isOnSale && regular != null) ...[
          const SizedBox(height: 2),
          Text(
            regular.formatted(),
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              color: context.scaffoldMuted,
              decoration: TextDecoration.lineThrough,
              decorationColor: context.scaffoldMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// "See products in All departments (12) or in Living Room Sets, Home
/// Furniture": the first link opens the full results, the others the
/// category's listing. Scoped to a category, the first link names it instead.
///
/// The links are text spans with tap recognizers, not widget spans: the
/// sentence mixes Arabic with Latin category names, and widget-span
/// placeholders came out in the wrong places in a right-to-left line.
class _SeeProductsIn extends StatefulWidget {
  const _SeeProductsIn({
    required this.allLabel,
    required this.total,
    required this.categories,
    required this.onAll,
  });

  final String allLabel;
  final int total;
  final List<SearchCategory> categories;
  final VoidCallback onAll;

  @override
  State<_SeeProductsIn> createState() => _SeeProductsInState();
}

class _SeeProductsInState extends State<_SeeProductsIn> {
  final List<TapGestureRecognizer> _recognizers = [];

  static const TextStyle _linkStyle = TextStyle(
    fontWeight: FontWeight.w600,
    color: AppColors.accentStrong,
  );

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TextSpan _link(String label, VoidCallback onTap) {
    final recognizer = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(recognizer);
    return TextSpan(text: label, style: _linkStyle, recognizer: recognizer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = widget.categories;
    // Recognizers belong to the spans of one build.
    _disposeRecognizers();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 6, 16, 8),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 12,
            height: 16 / 12,
            color: context.scaffoldMuted,
          ),
          children: [
            TextSpan(text: '${l10n.searchSeeProductsIn} '),
            _link('${widget.allLabel} (${widget.total})', widget.onAll),
            if (categories.isNotEmpty) ...[
              TextSpan(text: ' ${l10n.searchOrIn} '),
              for (var i = 0; i < categories.length; i++) ...[
                if (i > 0) TextSpan(text: l10n.searchListSeparator),
                _link(
                  categories[i].name,
                  () => openSearchCategory(
                    context,
                    categories[i].uid,
                    categories[i].name,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The bar pinned above the keyboard: top categories of the result as chips,
/// "View all N results", and "Search by algolia".
class _PinnedActions extends StatelessWidget {
  const _PinnedActions({
    required this.total,
    required this.categories,
    required this.onViewAll,
  });

  final int total;
  final List<SearchCategory> categories;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (categories.isNotEmpty) ...[
              Row(
                children: [
                  SizedBox(
                    width: 68,
                    child: Text(
                      l10n.searchCategoriesLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.scaffoldMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < categories.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            SearchOutlinedChip(
                              label: categories[i].name,
                              onTap: () => openSearchCategory(
                                context,
                                categories[i].uid,
                                categories[i].name,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            // The theme's navy 52 pt button; styled on the Text, as a
            // ButtonStyle textStyle would drop the theme font.
            FilledButton(
              onPressed: onViewAll,
              child: Text(
                l10n.searchViewAllResults(total),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const SearchByAlgolia(),
          ],
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.scaffoldMuted),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
        ],
      ),
    );
  }
}

/// What the scope sheet returns: the chosen category, or null for all of them.
class SearchScopePick {
  const SearchScopePick(this.category);

  final Category? category;
}

/// The scope picker behind "All categories ▾": all categories, then every
/// top-level category that holds products.
class SearchScopeSheet extends ConsumerWidget {
  const SearchScopeSheet({super.key, this.selectedUid});

  final String? selectedUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final choices = ref.watch(searchCategoryChoicesProvider);
    final categories = choices.valueOrNull;

    Widget row(Category? category) => _ScopeRow(
      label: category?.name ?? l10n.searchAllCategories,
      selected: category?.uid == selectedUid,
      onTap: () => Navigator.of(context).pop(SearchScopePick(category)),
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.searchScopeTitle,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkHeading,
                  ),
                ),
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.borderDefault,
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  row(null),
                  if (categories != null)
                    for (final category in categories) row(category)
                  else if (choices.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScopeRow extends StatelessWidget {
  const _ScopeRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 13, 20, 13),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppColors.brandPrimary : AppColors.inkMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: AppColors.inkHeading,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
