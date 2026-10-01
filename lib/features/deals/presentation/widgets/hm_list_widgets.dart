import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/widgets/product_card.dart';

/// The list pages' app bar (Figma 10b–10e "App bar"): [HubTopBar] — ← back,
/// the title, and search / cart (or [actions]) on the end side — with the
/// 1 px `border/subtle` rule Figma draws on the bar's last pixel (all but the
/// brand page's, whose header carries the rule: [divider] false).
class HmTitleAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HmTitleAppBar({
    super.key,
    required this.title,
    this.actions,
    this.divider = true,
  });

  final String title;

  /// Defaults to search and cart.
  final List<Widget>? actions;
  final bool divider;

  @override
  Size get preferredSize => const Size.fromHeight(HubTopBar.rowHeight);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final bar = HubTopBar(
      title: title,
      showBack: true,
      actions:
          actions ??
          [
            HubIconButton(
              icon: HubIcons.search,
              tooltip: l10n.navSearch,
              onPressed: () => context.push(AppRoutes.search),
            ),
            // The frames' app bars space their children 4 px apart.
            const SizedBox(width: 4),
            HubIconButton(
              icon: HubIcons.shoppingCart,
              tooltip: l10n.navCart,
              onPressed: () => context.go(AppRoutes.cart),
            ),
          ],
    );
    if (!divider) return bar;
    return Stack(
      children: [
        bar,
        // Inside the bar's 56 px, not under it: the frames' body starts where
        // the bar ends.
        const PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          height: 1,
          child: ColoredBox(color: AppColors.borderSubtle),
        ),
      ],
    );
  }
}

/// A horizontal row of `HubChip`s (Figma "filters": 36 px high, 8 apart).
///
/// By default the row sits inside the page's 16 px gutters and is clipped at
/// them, as the 10b / 10c / 10e frames' `filters` rows are ([padded] false
/// when the parent already has the gutters); [bleed] runs it to the screen's
/// edges with the gutter as scroll padding (Figma 12's rows).
class HmChipRow extends StatelessWidget {
  const HmChipRow({
    super.key,
    required this.chips,
    this.bleed = false,
    this.padded = true,
  });

  final List<Widget> chips;
  final bool bleed;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: bleed
            ? const EdgeInsets.symmetric(horizontal: 16)
            : EdgeInsets.zero,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
    return bleed || !padded
        ? row
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: row,
          );
  }
}

/// An outlined pill with a glyph (Figma 10b / 10e toolbar: "Biggest discount",
/// "Filters"): 30 px high — 6 px of padding over a 16 px line, inside a 1 px
/// `border/default` outline — a 14 px icon and Caption Strong.
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
          // 10 + 6 as drawn, plus the 1 px outline the shape paints inside.
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.inkHeading),
              const SizedBox(width: 4),
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

/// The two-column product grid of the list pages (Figma 10b, 10e): 12 px
/// between the cards both ways — the PLP's [productGridDelegate] keeps 16 and
/// 18.
ProductGridDelegate hmGridDelegate(BuildContext context) => ProductGridDelegate(
  infoHeight: ProductCardMetrics.infoHeight(context),
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
);
