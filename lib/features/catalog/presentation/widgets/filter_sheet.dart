import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import '../../domain/aggregation.dart';
import 'filter_parts.dart';
import 'sheet_chrome.dart';
import 'sort_sheet.dart';

/// Result of the filter sheet: the selected attribute facets, an optional price
/// range (null bounds = unbounded on that side), the Discount / Rating
/// thresholds and — when the sheet offered them — the sort picked.
class FilterResult {
  const FilterResult({
    required this.attributes,
    this.priceFrom,
    this.priceTo,
    this.minDiscount,
    this.minRating,
    this.minRatingStars,
    this.sort,
  });

  final Map<String, Set<String>> attributes;
  final double? priceFrom;
  final double? priceTo;
  final int? minDiscount;

  /// The rating threshold in whole stars (4★ & up = 4; a half star rounds
  /// down), for the listings that filter on whole stars.
  final int? minRating;

  /// The rating threshold exactly as picked: 4.5, 4, 3.5.
  final double? minRatingStars;

  /// The choice picked among [FilterSheet.sortChoices]; null when the sheet
  /// had none.
  final Object? sort;
}

/// The facets that name a store: the seller attribute on the listings
/// (`VENDORID`, an equal-type filter whose options are vendor ids) and
/// Algolia's seller facet (whose values already are names). The listings'
/// other seller attribute, `vendor_id`, is a match filter that the facet
/// filters can't send; the sheet never offers it.
const Set<String> kStoreFacetCodes = <String>{'VENDORID', 'seller'};

/// Filters bottom sheet (Figma 11 "Filters (full sheet)"): Sort by, Price with
/// its Min / Max, Customer rating, the Store and every other facet of the
/// listing as chips, and a "Show N results" button. Sections the source can't
/// filter on stay out — GraphQL on Hub Market has no discount or rating
/// attribute (see [kDiscountFilterSupported]; Algolia search can rate).
///
/// The `price` facet drives the slider bounds. Returns a [FilterResult] on the
/// button; Reset clears the selection and keeps the sheet open.
class FilterSheet extends StatefulWidget {
  const FilterSheet({
    super.key,
    required this.aggregations,
    required this.initial,
    required this.currency,
    this.initialPriceFrom,
    this.initialPriceTo,
    this.initialMinDiscount,
    this.initialMinRating,
    this.showDiscount = kDiscountFilterSupported,
    this.showRating = kRatingFilterSupported,
    this.sortChoices = const <SortChoice<Object>>[],
    this.initialSort,
    this.resultCount,
    this.countFor,
    this.storeNames = const <String, String>{},
    this.showHandle = false,
  });

  final List<Aggregation> aggregations;
  final Map<String, Set<String>> initial;
  final String currency;
  final double? initialPriceFrom;
  final double? initialPriceTo;
  final int? initialMinDiscount;

  /// In stars (4 or 4.5); a whole number is the listings' existing value.
  final num? initialMinRating;

  /// Whether the "N% or more" and "N★ & up" sections are offered.
  final bool showDiscount;
  final bool showRating;

  /// The "Sort by" chips; the section is left out without any.
  final List<SortChoice<Object>> sortChoices;
  final Object? initialSort;

  /// How many results the listing has now — the button's number until a count
  /// for the selection arrives. Without it, and without [countFor], the button
  /// says "Apply Filters".
  final int? resultCount;

  /// How many results a selection would give; asked (debounced) as the
  /// selection changes. Null leaves the button on [resultCount].
  final Future<int?> Function(FilterResult selection)? countFor;

  /// Vendor id → store name, for the facets that carry vendor ids; such a
  /// facet shows only the stores it can name, and none without any.
  final Map<String, String> storeNames;

  /// Draws the grab handle. The sheet opened through `showCatalogSheet` asks
  /// for it; one opened with Material's own handle must not.
  final bool showHandle;

  /// Discount thresholds shown on the website ("N% or more"), high → low.
  static const List<int> discountBuckets = [50, 40, 30, 20];

  /// Rating thresholds of Figma 11 ("4.5★ & up", "4★ & up", "3.5★ & up").
  static const List<double> ratingBuckets = [4.5, 4, 3.5];

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

/// A facet as the sheet lists it: the store facet (by whatever attribute),
/// then the others.
class _Facet {
  const _Facet(this.code, this.label, this.options, {this.isStore = false});

  final String code;
  final String label;
  final List<AggregationOption> options;
  final bool isStore;
}

class _FilterSheetState extends State<FilterSheet> {
  late final Map<String, Set<String>> _selection = {
    for (final entry in widget.initial.entries) entry.key: {...entry.value},
  };

  late int? _minDiscount = widget.initialMinDiscount;
  late double? _minRating = widget.initialMinRating?.toDouble();
  late Object? _sort = widget.initialSort;

  /// Overall price bounds parsed from the price aggregation, or null when the
  /// catalogue exposes no usable price facet.
  (double, double)? _bounds;
  late RangeValues _price;

  late int? _count = widget.resultCount;
  int _countToken = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _bounds = _priceBounds();
    final b = _bounds;
    if (b != null) {
      final from = (widget.initialPriceFrom ?? b.$1).clamp(b.$1, b.$2);
      final to = (widget.initialPriceTo ?? b.$2).clamp(b.$1, b.$2);
      _price = RangeValues(from, to <= from ? b.$2 : to);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  (double, double)? _priceBounds() {
    Aggregation? price;
    for (final a in widget.aggregations) {
      if (a.attributeCode == 'price') {
        price = a;
        break;
      }
    }
    if (price == null) return null;
    final nums = <double>[];
    for (final option in price.options) {
      for (final token in option.value.split(RegExp(r'[^0-9.]+'))) {
        final n = double.tryParse(token);
        if (n != null) nums.add(n);
      }
    }
    if (nums.length < 2) return null;
    nums.sort();
    final lo = nums.first;
    final hi = nums.last;
    return hi > lo ? (lo, hi) : null;
  }

  /// Something changed: rebuild, and ask what the selection would give.
  void _changed(VoidCallback change) {
    setState(change);
    final ask = widget.countFor;
    if (ask == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = ++_countToken;
      int? count;
      try {
        count = await ask(_result());
      } on Object {
        count = null;
      }
      if (!mounted || token != _countToken || count == null) return;
      setState(() => _count = count);
    });
  }

  void _toggle(String code, String value) => _changed(() {
    final set = _selection.putIfAbsent(code, () => <String>{});
    if (!set.add(value)) set.remove(value);
    if (set.isEmpty) _selection.remove(code);
  });

  void _clear() => _changed(() {
    _selection.clear();
    _minDiscount = null;
    _minRating = null;
    final b = _bounds;
    if (b != null) _price = RangeValues(b.$1, b.$2);
  });

  void _setPrice({double? from, double? to}) {
    final b = _bounds;
    if (b == null) return;
    var start = (from ?? _price.start).clamp(b.$1, b.$2);
    var end = (to ?? _price.end).clamp(b.$1, b.$2);
    if (start > end) {
      // A bound typed past the other: they swap, as a range does.
      (start, end) = (end, start);
    }
    _changed(() => _price = RangeValues(start, end));
  }

  /// Hands the selection back — after a Min or Max that is still being typed
  /// has been taken (it commits when it loses focus).
  Future<void> _apply() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    Navigator.of(context).pop(_result());
  }

  FilterResult _result() {
    final b = _bounds;
    // Only treat the price as an active filter when the user narrowed it.
    final narrowed = b != null && (_price.start > b.$1 || _price.end < b.$2);
    return FilterResult(
      attributes: {
        for (final e in _selection.entries) e.key: {...e.value},
      },
      priceFrom: narrowed ? _price.start : null,
      priceTo: narrowed ? _price.end : null,
      minDiscount: _minDiscount,
      minRating: _minRating?.floor(),
      minRatingStars: _minRating,
      sort: widget.sortChoices.isEmpty ? null : _sort,
    );
  }

  /// The facets the sheet lists: the store facet first, then the others in the
  /// listing's order. A facet of vendor ids shows the stores it can name.
  List<_Facet> _facets(AppLocalizations l10n) {
    final stores = <_Facet>[];
    final others = <_Facet>[];
    for (final facet in widget.aggregations) {
      if (facet.attributeCode == 'price' ||
          facet.attributeCode == 'vendor_id' ||
          facet.options.isEmpty) {
        continue;
      }
      if (kStoreFacetCodes.contains(facet.attributeCode)) {
        final named = facet.attributeCode == 'seller'
            ? facet.options
            : [
                for (final option in facet.options)
                  if (widget.storeNames[option.label.trim()] case final name?)
                    AggregationOption(
                      label: name,
                      value: option.value,
                      count: option.count,
                    ),
              ];
        if (named.isNotEmpty) {
          stores.add(
            _Facet(
              facet.attributeCode,
              l10n.filterStoreLabel,
              named,
              isStore: true,
            ),
          );
        }
        continue;
      }
      others.add(_Facet(facet.attributeCode, facet.label, facet.options));
    }
    return [...stores, ...others];
  }

  /// What a facet's caption says: how many stores there are, or the picks.
  String? _caption(AppLocalizations l10n, _Facet facet) {
    if (facet.isStore) return l10n.categoryStoreCount(facet.options.length);
    final picked = _selection[facet.code];
    if (picked == null || picked.isEmpty) return null;
    return [
      for (final option in facet.options)
        if (picked.contains(option.value)) option.label,
    ].join(', ');
  }

  String _buttonLabel(AppLocalizations l10n) {
    final count = _count;
    return count == null
        ? l10n.filterApplyLabel
        : l10n.filterShowResults(count);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final facets = _facets(l10n);
    final bounds = _bounds;

    final sections = <Widget>[
      if (widget.sortChoices.isNotEmpty)
        FilterSection(
          title: l10n.filterSortByLabel,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in widget.sortChoices)
                HubChip(
                  label: choice.label,
                  selected: choice.value == _sort,
                  onTap: () => _changed(() => _sort = choice.value),
                ),
            ],
          ),
        ),
      if (bounds != null)
        FilterSection(
          title: l10n.filterPriceCurrencyLabel(widget.currency),
          child: _PriceRange(
            bounds: bounds,
            values: _price,
            onSlide: (v) => _changed(() => _price = v),
            onMin: (n) => _setPrice(from: n?.toDouble()),
            onMax: (n) => _setPrice(to: n?.toDouble()),
          ),
        ),
      if (widget.showRating)
        FilterSection(
          title: l10n.filterRatingLabel,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final stars in FilterSheet.ratingBuckets)
                FilterChipButton(
                  selected: _minRating == stars,
                  onTap: () => _changed(
                    () => _minRating = _minRating == stars ? null : stars,
                  ),
                  child: _RatingLabel(stars: stars),
                ),
              HubChip(
                label: l10n.filterAll,
                selected: _minRating == null,
                onTap: () => _changed(() => _minRating = null),
              ),
            ],
          ),
        ),
      // Discount — fixed "N% or more" thresholds (single-select), only where
      // the store can filter on a discount attribute.
      if (widget.showDiscount)
        FilterSection(
          title: l10n.filterDiscountLabel,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final pct in FilterSheet.discountBuckets)
                HubChip(
                  label: l10n.filterDiscountOption(pct),
                  selected: _minDiscount == pct,
                  onTap: () => _changed(
                    () => _minDiscount = _minDiscount == pct ? null : pct,
                  ),
                ),
            ],
          ),
        ),
      for (final facet in facets)
        FilterSection(
          title: facet.label,
          caption: _caption(l10n, facet),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (facet.isStore)
                HubChip(
                  label: l10n.filterAllStores,
                  selected:
                      (_selection[facet.code] ?? const <String>{}).isEmpty,
                  onTap: () => _changed(() => _selection.remove(facet.code)),
                ),
              for (final option in facet.options)
                HubChip(
                  label: option.label,
                  selected:
                      _selection[facet.code]?.contains(option.value) ?? false,
                  onTap: () => _toggle(facet.code, option.value),
                ),
            ],
          ),
        ),
    ];

    return LayoutBuilder(
      // A full sheet stops short of the status bar, as the frame's does — and
      // sits above the keyboard while a Min or Max is typed.
      builder: (context, constraints) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                constraints.maxHeight -
                MediaQuery.paddingOf(context).top -
                sheetTopGap -
                MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showHandle) const SheetHandle(),
              SheetHeader(
                title: l10n.filtersLabel,
                action: InkWell(
                  onTap: _clear,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l10n.filterResetLabel,
                      style: t.bodyStrong.copyWith(
                        color: AppColors.accentStrong,
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    for (var i = 0; i < sections.length; i++) ...[
                      if (i > 0) const SizedBox(height: 22),
                      sections[i],
                    ],
                  ],
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _apply,
                        child: Text(_buttonLabel(l10n)),
                      ),
                    ),
                    const SheetBottomSpace(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The price slider (28 pt) over the Min and Max boxes, 10 pt apart.
class _PriceRange extends StatelessWidget {
  const _PriceRange({
    required this.bounds,
    required this.values,
    required this.onSlide,
    required this.onMin,
    required this.onMax,
  });

  final (double, double) bounds;
  final RangeValues values;
  final ValueChanged<RangeValues> onSlide;
  final ValueChanged<int?> onMin;
  final ValueChanged<int?> onMax;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        SizedBox(
          height: 28,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              rangeThumbShape: const PriceThumbShape(),
              rangeTrackShape: const PriceTrackShape(),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: AppColors.brandPrimary,
              inactiveTrackColor: AppColors.borderSubtle,
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: RangeSlider(
              min: bounds.$1,
              max: bounds.$2,
              values: values,
              onChanged: onSlide,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          spacing: 12,
          children: [
            Expanded(
              child: PriceField(
                label: l10n.filterMinLabel,
                value: values.start.round(),
                onSubmitted: onMin,
              ),
            ),
            Expanded(
              child: PriceField(
                label: l10n.filterMaxLabel,
                value: values.end.round(),
                onSubmitted: onMax,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// "4.5★ & up": the number, a gold star, the wording.
class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.stars});

  final double stars;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = stars == stars.roundToDouble()
        ? '${stars.round()}'
        : stars.toStringAsFixed(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(number),
        // The frame's ★ is text in the chip's ink, not a gold star.
        const Icon(Icons.star, size: 14),
        const SizedBox(width: 3),
        Text(l10n.filterRatingAndUp),
      ],
    );
  }
}
