import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/presentation/cart_controller.dart';
import '../../l10n/l10n.dart';
import '../routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/hub_icons.dart';

/// Persistent bottom navigation (Home · Categories · Cart · Wishlist · Account),
/// Figma component "Tab bar": white, a 1 px `border/subtle` rule on top, five
/// equal tabs of a 24 px outline icon over a 12 px label. The active tab turns
/// orange (icon `accent`, label `accent-strong`, label one weight up); the rest
/// are muted grey. Only the cart carries a count badge (orange pill, white 11 px).
class HubBottomNav extends ConsumerWidget {
  const HubBottomNav({super.key, required this.current});

  final AppTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cartCount = ref.watch(
      cartControllerProvider.select((s) => s.itemCount),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        // Figma: 84 = 1 rule + 55 tabs + 28 home-indicator padding; the last
        // part is the device's own bottom inset here. The tabs grow with the
        // user's text size instead of overflowing.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 55),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NavItem(
                  tab: AppTab.home,
                  current: current,
                  icon: HubIcons.house,
                  label: l10n.navHome,
                ),
                _NavItem(
                  tab: AppTab.categories,
                  current: current,
                  icon: HubIcons.layoutGrid,
                  label: l10n.navCategories,
                ),
                _NavItem(
                  tab: AppTab.cart,
                  current: current,
                  icon: HubIcons.shoppingCart,
                  label: l10n.navCart,
                  badge: cartCount,
                ),
                _NavItem(
                  tab: AppTab.wishlist,
                  current: current,
                  icon: HubIcons.heart,
                  label: l10n.navWishlist,
                ),
                _NavItem(
                  tab: AppTab.account,
                  current: current,
                  icon: HubIcons.user,
                  label: l10n.navAccount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.current,
    required this.icon,
    required this.label,
    this.badge,
  });

  final AppTab tab;
  final AppTab current;
  final IconData icon;
  final String label;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final selected = tab == current;
    final text = AppTextStyles.of(context);
    final labelStyle = (selected ? text.captionStrong : text.caption).copyWith(
      color: selected ? AppColors.accentStrong : AppColors.inkMuted,
    );
    final count = badge ?? 0;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        child: InkWell(
          // Always navigate to the tab root, even when re-tapping the active tab.
          onTap: () => context.go(tab.route),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        icon,
                        size: 24,
                        color: selected
                            ? AppColors.accent
                            : AppColors.inkMuted,
                      ),
                      if (count > 0)
                        PositionedDirectional(
                          start: 14,
                          top: -5,
                          child: _CountBadge(count: count),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The cart's count: an orange pill (Figma `badge`: px 5, py 1, 11 px Bold).
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final text = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textDirection: TextDirection.ltr,
        style: text.micro.copyWith(color: Colors.white),
      ),
    );
  }
}
