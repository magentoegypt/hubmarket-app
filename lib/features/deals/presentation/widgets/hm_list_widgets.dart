import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';

/// The list pages' app bar (Figma 10b–10e): ← back, the title, and search /
/// cart (or [actions]) on the end side.
class HmTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HmTitleAppBar({super.key, required this.title, this.actions});

  final String title;

  /// Defaults to search and cart.
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return AppBar(
      toolbarHeight: 56,
      centerTitle: false,
      titleSpacing: 4,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      scrolledUnderElevation: 0,
      shape: const Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, size: 22),
        color: AppColors.inkHeading,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.maybePop(context),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.heading2.copyWith(color: AppColors.inkHeading),
      ),
      actions:
          actions ??
          [
            IconButton(
              icon: const Icon(Icons.search, size: 22),
              color: AppColors.inkHeading,
              tooltip: MaterialLocalizations.of(context).searchFieldLabel,
              onPressed: () => context.push(AppRoutes.search),
            ),
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined, size: 22),
              color: AppColors.inkHeading,
              onPressed: () => context.go(AppRoutes.cart),
            ),
            const SizedBox(width: 4),
          ],
    );
  }
}

/// A filter chip of the list pages (Figma component "Chip"): 36 pt, navy when
/// selected, outlined otherwise.
class HmFilterChip extends StatelessWidget {
  const HmFilterChip({
    super.key,
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
      child: Material(
        color: selected ? AppColors.brandPrimary : Colors.white,
        shape: StadiumBorder(
          side: selected
              ? BorderSide.none
              : const BorderSide(color: AppColors.borderStrong),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              // As wide as its label, in a row or in a Wrap alike.
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: t.bodyStrong.copyWith(
                    color: selected ? Colors.white : AppColors.inkHeading,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A horizontal row of [HmFilterChip]s.
class HmChipRow extends StatelessWidget {
  const HmChipRow({super.key, required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: chips.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, i) => chips[i],
    ),
  );
}

/// An outlined pill with a glyph (Figma "Biggest discount", "Filters").
class HmPillButton extends StatelessWidget {
  const HmPillButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Material(
      color: Colors.white,
      shape: const StadiumBorder(
        side: BorderSide(color: AppColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.inkHeading),
              const SizedBox(width: 6),
              Text(
                label,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
