import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/aggregation.dart';

/// Result of the filter sheet: the selected attribute facets, an optional price
/// range (null bounds = unbounded on that side), and the Discount / Rating
/// thresholds. Sort lives in its own sheet ([SortSheet]) — QA 86d3m97au wants
/// Filter and Sort as two separate controls.
class FilterResult {
  const FilterResult({
    required this.attributes,
    this.priceFrom,
    this.priceTo,
    this.minDiscount,
    this.minRating,
  });

  final Map<String, Set<String>> attributes;
  final double? priceFrom;
  final double? priceTo;
  final int? minDiscount;
  final int? minRating;
}

/// Filter-only bottom sheet (Figma "Filters (Sheet)"). Flat labelled sections:
/// Price Range (slider), one section per aggregation facet (Category,
/// Manufacturer, …), then the website's fixed-bucket Discount and Rating
/// thresholds. The `price` facet drives the slider bounds. Returns a
/// [FilterResult] on Apply. Sorting is handled separately by [SortSheet].
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
  });

  final List<Aggregation> aggregations;
  final Map<String, Set<String>> initial;
  final String currency;
  final double? initialPriceFrom;
  final double? initialPriceTo;
  final int? initialMinDiscount;
  final int? initialMinRating;

  /// Discount thresholds shown on the website ("N% or more"), high → low.
  static const List<int> discountBuckets = [50, 40, 30, 20];

  /// Rating thresholds shown on the website ("N★ & above"), high → low.
  static const List<int> ratingBuckets = [4, 3, 2, 1];

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final Map<String, Set<String>> _selection = {
    for (final entry in widget.initial.entries) entry.key: {...entry.value},
  };

  late int? _minDiscount = widget.initialMinDiscount;
  late int? _minRating = widget.initialMinRating;

  /// Overall price bounds parsed from the price aggregation, or null when the
  /// catalogue exposes no usable price facet.
  (double, double)? _bounds;
  late RangeValues _price;

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

  void _toggle(String code, String value) {
    setState(() {
      final set = _selection.putIfAbsent(code, () => <String>{});
      if (!set.add(value)) set.remove(value);
      if (set.isEmpty) _selection.remove(code);
    });
  }

  void _clear() {
    setState(() {
      _selection.clear();
      _minDiscount = null;
      _minRating = null;
      final b = _bounds;
      if (b != null) _price = RangeValues(b.$1, b.$2);
    });
  }

  FilterResult _result() {
    final b = _bounds;
    // Only treat the price as an active filter when the user narrowed it.
    final narrowed = b != null && (_price.start > b.$1 || _price.end < b.$2);
    return FilterResult(
      attributes: _selection,
      priceFrom: narrowed ? _price.start : null,
      priceTo: narrowed ? _price.end : null,
      minDiscount: _minDiscount,
      minRating: _minRating,
    );
  }

  String _money(double v) => '${widget.currency} ${v.round()}';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final facets = widget.aggregations
        .where((a) => a.attributeCode != 'price' && a.options.isNotEmpty)
        .toList();
    final bounds = _bounds;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header — title + Reset.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 12, 8),
            child: Row(
              children: [
                Text(
                  l10n.filtersLabel,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clear,
                  child: Text(
                    l10n.filterResetLabel,
                    style: const TextStyle(color: AppColors.brandPrimary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                // Price Range.
                if (bounds != null) ...[
                  _SectionLabel(text: l10n.filterPriceRangeLabel, trailing: Text(
                    '${_money(_price.start)} — ${_money(_price.end)}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: AppColors.brandPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  )),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 4),
                    child: RangeSlider(
                      min: bounds.$1,
                      max: bounds.$2,
                      values: _price,
                      labels: RangeLabels(
                        _money(_price.start),
                        _money(_price.end),
                      ),
                      onChanged: (v) => setState(() => _price = v),
                    ),
                  ),
                ],
                // Attribute facets (Category, Manufacturer, …).
                for (final facet in facets) ...[
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderDefault,
                  ),
                  _SectionLabel(text: facet.label),
                  for (final option in facet.options)
                    _FacetRow(
                      label: option.label,
                      count: option.count,
                      selected:
                          _selection[facet.attributeCode]?.contains(
                            option.value,
                          ) ??
                          false,
                      onTap: () => _toggle(facet.attributeCode, option.value),
                    ),
                  const SizedBox(height: 8),
                ],
                // Discount — fixed "N% or more" thresholds (single-select).
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderDefault,
                ),
                _SectionLabel(text: l10n.filterDiscountLabel),
                for (final pct in FilterSheet.discountBuckets)
                  _ThresholdRow(
                    selected: _minDiscount == pct,
                    onTap: () => setState(
                      () => _minDiscount = _minDiscount == pct ? null : pct,
                    ),
                    child: Text(
                      l10n.filterDiscountOption(pct),
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.inkHeading,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // Rating — fixed "N★ & above" thresholds (single-select).
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.borderDefault,
                ),
                _SectionLabel(text: l10n.filterRatingLabel),
                for (final stars in FilterSheet.ratingBuckets)
                  _ThresholdRow(
                    selected: _minRating == stars,
                    onTap: () => setState(
                      () => _minRating = _minRating == stars ? null : stars,
                    ),
                    child: _RatingLabel(stars: stars),
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
          // Footer — Clear All (fixed 120) + Apply Filters (fills). Figma 68:70.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.inkHeading,
                      side: const BorderSide(
                        color: AppColors.borderDefault,
                        width: 1.4,
                      ),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(l10n.filterClearAllLabel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_result()),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: Text(l10n.filterApplyLabel),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A section header label with an optional trailing widget (e.g. the live price
/// range readout).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 14, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
                color: AppColors.inkHeading,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A "N★ & above" rating label: number · gold star · localized "& above".
class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.stars});
  final int stars;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$stars',
          style: const TextStyle(fontSize: 15, color: AppColors.inkHeading),
        ),
        const SizedBox(width: 3),
        const Icon(Icons.star, size: 16, color: Color(0xFFF5A623)),
        const SizedBox(width: 6),
        Text(
          l10n.filterRatingAndAbove,
          style: const TextStyle(fontSize: 15, color: AppColors.inkHeading),
        ),
      ],
    );
  }
}

/// A single-select threshold row (Discount / Rating): rounded-square check +
/// arbitrary label child.
class _ThresholdRow extends StatelessWidget {
  const _ThresholdRow({
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 9, 20, 9),
        child: Row(
          children: [
            _CheckSquare(selected: selected),
            const SizedBox(width: 12),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// One selectable facet option: rounded-square checkbox · label · right-aligned
/// count (Figma Brand row).
class _FacetRow extends StatelessWidget {
  const _FacetRow({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 9, 20, 9),
        child: Row(
          children: [
            _CheckSquare(selected: selected),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.inkHeading,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckSquare extends StatelessWidget {
  const _CheckSquare({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: selected ? AppColors.brandPrimary : Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: selected ? AppColors.brandPrimary : AppColors.borderDefault,
        width: 1.5,
      ),
    ),
    child: selected
        ? const Icon(Icons.check, size: 14, color: Colors.white)
        : null,
  );
}
