import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/presentation/cart_controller.dart';
import '../../features/wishlist/presentation/wishlist_controller.dart';
import '../../l10n/l10n.dart';
import '../routes.dart';
import '../theme/app_colors.dart';

/// Persistent bottom navigation (Home · Categories · Cart · Wishlist · Account).
/// Figma: a thin top divider, and the active tab marked by a navy top bar +
/// navy icon/label (inactive tabs are muted grey). Live cart + wishlist
/// count badges.
class HubBottomNav extends ConsumerWidget {
  const HubBottomNav({super.key, required this.current});

  final AppTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cartCount = ref.watch(
      cartControllerProvider.select((s) => s.itemCount),
    );
    final wishlistCount = ref.watch(
      wishlistControllerProvider.select((s) => s.entries.length),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _NavItem(
                tab: AppTab.home,
                current: current,
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: l10n.navHome,
              ),
              _NavItem(
                tab: AppTab.categories,
                current: current,
                icon: Icons.grid_view_outlined,
                activeIcon: Icons.grid_view,
                label: l10n.navCategories,
              ),
              _NavItem(
                tab: AppTab.cart,
                current: current,
                icon: Icons.shopping_cart_outlined,
                activeIcon: Icons.shopping_cart,
                label: l10n.navCart,
                badge: cartCount,
              ),
              _NavItem(
                tab: AppTab.wishlist,
                current: current,
                icon: Icons.favorite_border,
                activeIcon: Icons.favorite,
                label: l10n.navWishlist,
                badge: wishlistCount,
              ),
              _NavItem(
                tab: AppTab.account,
                current: current,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: l10n.navAccount,
              ),
            ],
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
    required this.activeIcon,
    required this.label,
    this.badge,
  });

  final AppTab tab;
  final AppTab current;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final selected = tab == current;
    final color = selected ? AppColors.brandPrimary : AppColors.inkMuted;
    return Expanded(
      child: InkWell(
        // Always navigate to the tab root, even when re-tapping the active tab.
        onTap: () => context.go(tab.route),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            // Top indicator bar (Figma) — navy when active.
            Container(
              width: 18,
              height: 3,
              decoration: BoxDecoration(
                color: selected ? AppColors.brandPrimary : Colors.transparent,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 9),
            Badge(
              isLabelVisible: (badge ?? 0) > 0,
              label: Text('${badge ?? 0}'),
              child: Icon(selected ? activeIcon : icon, color: color, size: 24),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
