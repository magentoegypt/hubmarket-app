import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../l10n/l10n.dart';
import '../../data/catalog_repository.dart';
import 'sheet_chrome.dart';

/// Sort-only bottom sheet — the second of the listing's two separate controls
/// (QA 86d3m97au: Filter and Sort as distinct tabs; the Filters sheet repeats
/// the choice as "Sort by" chips, Figma 11). Lists the sorts the backend can
/// do — Relevance, Lowest price, Highest price, Name: A–Z. "Newest first"
/// renders disabled ("Coming soon") until the backend adds the sort field (see
/// [kNewestSortSupported]).
///
/// Pops the chosen [ProductSortField] on tap, or null when dismissed.
class SortSheet extends StatelessWidget {
  const SortSheet({
    super.key,
    required this.current,
    this.relevanceLabel,
    this.showHandle = false,
  });

  final ProductSortField current;

  /// Label for the default option. The listing and the search results both say
  /// "Relevance" (Figma 10, 11); defaults to the localized one.
  final String? relevanceLabel;

  /// Draws the grab handle (see [showCatalogSheet]).
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget row(ProductSortField field, String label) => _SortRow(
      label: label,
      selected: current == field,
      onTap: () => Navigator.of(context).pop(field),
    );

    return _SortSheetFrame(
      showHandle: showHandle,
      title: l10n.sortLabel,
      rows: [
        row(ProductSortField.relevance, relevanceLabel ?? l10n.sortRelevance),
        row(ProductSortField.priceAsc, l10n.sortLowestPrice),
        row(ProductSortField.priceDesc, l10n.sortHighestPrice),
        // Newest first — disabled (pending the backend `newest_sort` field).
        _SortRow(
          label: l10n.sortNewestFirst,
          selected: false,
          enabled: kNewestSortSupported,
          trailingNote: kNewestSortSupported ? null : l10n.sortComingSoon,
          onTap: null,
        ),
        row(ProductSortField.nameAsc, l10n.sortNameAz),
      ],
    );
  }
}

/// One choice of a [SortChoiceSheet].
typedef SortChoice<T> = ({T value, String label});

/// A sort sheet over a list the data decides — search results offer
/// relevance plus whatever the engine can sort by (Algolia: the replicas the
/// admin configured). Looks like [SortSheet]; pops the chosen value, or null
/// when dismissed.
class SortChoiceSheet<T> extends StatelessWidget {
  const SortChoiceSheet({
    super.key,
    required this.choices,
    required this.current,
    this.showHandle = false,
  });

  final List<SortChoice<T>> choices;
  final T current;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _SortSheetFrame(
      showHandle: showHandle,
      title: l10n.sortLabel,
      rows: [
        for (final choice in choices)
          _SortRow(
            label: choice.label,
            selected: choice.value == current,
            onTap: () => Navigator.of(context).pop(choice.value),
          ),
      ],
    );
  }
}

/// The sheet around the rows: handle, title over its rule, the rows, and the
/// bottom inset.
class _SortSheetFrame extends StatelessWidget {
  const _SortSheetFrame({
    required this.showHandle,
    required this.title,
    required this.rows,
  });

  final bool showHandle;
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (showHandle) const SheetHandle(),
      SheetHeader(title: title),
      ...rows,
      const SheetBottomSpace(),
    ],
  );
}

/// One sort option row: the label, and either a check on the chosen one or a
/// "Coming soon" note. Muted and non-tappable when [enabled] is false.
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
    final t = AppTextStyles.of(context);
    final style = (selected ? t.bodyStrong : t.body).copyWith(
      color: enabled ? AppColors.inkHeading : AppColors.inkMuted,
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(child: Text(label, style: style)),
              if (trailingNote != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.borderDefault),
                  ),
                  child: Text(
                    trailingNote!,
                    style: t.micro.copyWith(
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              else if (selected)
                const Icon(
                  HubIcons.check,
                  size: 20,
                  color: AppColors.brandPrimary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
