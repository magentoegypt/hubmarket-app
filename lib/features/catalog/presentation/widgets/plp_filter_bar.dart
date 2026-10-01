import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../l10n/l10n.dart';

/// A chip of the listing's filter bar after the Filters one.
class PlpChip {
  const PlpChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;

  /// An applied filter: navy, and a tap takes it off.
  final bool selected;
}

/// The chips under the listing's app bar (Figma 10 "filter-bar"): the Filters
/// chip — orange with its count while filters are on — then the applied
/// filters (navy) and the quick ones (outlined), scrolling sideways. 36 pt
/// chips, 8 apart, 16 in from the start, 4 above and 10 below.
class PlpFilterBar extends StatelessWidget {
  const PlpFilterBar({
    super.key,
    required this.activeCount,
    required this.onFilters,
    this.chips = const <PlpChip>[],
    this.bottom = 10,
  });

  /// How many filters are on; 0 draws the Filters chip quietly.
  final int activeCount;
  final VoidCallback onFilters;
  final List<PlpChip> chips;

  /// The space under the chips.
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsetsDirectional.fromSTEB(16, 4, 16, bottom),
      child: Row(
        spacing: 8,
        children: [
          _FiltersChip(count: activeCount, onTap: onFilters),
          for (final chip in chips)
            HubChip(
              label: chip.label,
              selected: chip.selected,
              onTap: chip.onTap,
            ),
        ],
      ),
    );
  }
}

/// "Filters · 2": the sliders icon and the label; with filters on, an
/// accent-tinted pill with a 1 pt accent outline.
class _FiltersChip extends StatelessWidget {
  const _FiltersChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final active = count > 0;
    final ink = active ? AppColors.accentStrong : AppColors.inkHeading;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.accentSubtle : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? AppColors.accent : AppColors.borderStrong,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    Icon(HubIcons.slidersHorizontal, size: 16, color: ink),
                    Text(
                      active
                          ? '${l10n.filtersLabel} · $count'
                          : l10n.filtersLabel,
                      style: t.bodyStrong.copyWith(color: ink),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
