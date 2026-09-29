import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';

/// Sort-only bottom sheet — the second of the PLP's two separate controls
/// (QA 86d3m97au: Filter and Sort as distinct tabs). Lists the website's sort
/// options in the same order — Featured, Price: Low to High, Price: High to Low,
/// Newest First, Name: A–Z. "Newest First" renders disabled ("Coming soon")
/// until the backend adds the sort field (see [kNewestSortSupported]).
///
/// Pops the chosen [ProductSortField] on tap, or null when dismissed.
class SortSheet extends StatelessWidget {
  const SortSheet({super.key, required this.current, this.relevanceLabel});

  final ProductSortField current;

  /// Label for the default option. The PLP shows "Featured" (catalogue/position
  /// order); search results show "Relevance". Defaults to the localized
  /// "Featured".
  final String? relevanceLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget row(ProductSortField field, String label) => _SortRow(
      label: label,
      selected: current == field,
      onTap: () => Navigator.of(context).pop(field),
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l10n.sortLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
          // Website order: Featured, Price ↑, Price ↓, Newest First, Name A–Z.
          row(ProductSortField.relevance, relevanceLabel ?? l10n.sortFeatured),
          row(ProductSortField.priceAsc, l10n.sortPriceLowHigh),
          row(ProductSortField.priceDesc, l10n.sortPriceHighLow),
          // Newest First — disabled (pending the backend `newest_sort` field).
          _SortRow(
            label: l10n.sortNewest,
            selected: false,
            enabled: kNewestSortSupported,
            trailingNote: kNewestSortSupported ? null : l10n.sortComingSoon,
            onTap: null,
          ),
          row(ProductSortField.nameAsc, l10n.sortNameAz),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// One sort option row: a radio indicator, the label, and either a selected
/// check or a "Coming soon" note. Muted and non-tappable when [enabled] is false.
class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.trailingNote,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool enabled;
  final String? trailingNote;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.inkHeading : AppColors.inkMuted;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 13, 20, 13),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? AppColors.brandPrimary
                  : (enabled ? AppColors.inkMuted : AppColors.borderDefault),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            if (trailingNote != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.borderDefault),
                ),
                child: Text(
                  trailingNote!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
