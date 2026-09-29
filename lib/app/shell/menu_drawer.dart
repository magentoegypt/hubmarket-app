import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/store/store_controller.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/customer_avatar.dart';
import '../../core/widgets/language_toggle.dart';
import '../../features/account/data/account_repository.dart';
import '../../features/auth/presentation/auth_controller.dart';
import '../../features/catalog/domain/category.dart';
import '../../features/catalog/presentation/catalog_providers.dart';
import '../../features/catalog/presentation/category_icons.dart';
import '../../features/wishlist/presentation/wishlist_controller.dart';
import '../../l10n/l10n.dart';
import '../routes.dart';
import '../theme/app_colors.dart';

/// Side navigation drawer: brand header, customer profile header, SHOP
/// categories (live), ACCOUNT links, a bottom language toggle, and Log Out.
/// RTL flips the panel automatically via Directionality.
class MenuDrawer extends ConsumerWidget {
  const MenuDrawer({super.key});

  void _close(BuildContext context) => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final store = ref.watch(storeControllerProvider);
    final categories = ref.watch(categoryTreeProvider);
    final auth = ref.watch(authControllerProvider);

    return Drawer(
      // Figma: white panel; only the profile strip is tinted (Material 3 would
      // otherwise tint the whole surface from the navy seed).
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Brand header (Figma): HUB MARKET lockup centered, close (×) pinned to
            // the top trailing corner (flips to the leading side in RTL).
            SizedBox(
              height: 56,
              child: Stack(
                children: [
                  const Center(child: BrandLogo(height: 40)),
                  PositionedDirectional(
                    top: 4,
                    end: 4,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: AppColors.inkHeading,
                      ),
                      onPressed: () => _close(context),
                    ),
                  ),
                ],
              ),
            ),
            _ProfileHeader(
              name: auth.isAuthenticated ? (auth.customer?.fullName ?? '') : '',
              subtitle: auth.isAuthenticated
                  ? (auth.customer?.email ?? '')
                  : l10n.accountGuestTitle,
              avatarUrl: auth.isAuthenticated ? auth.customer?.avatarUrl : null,
              isAuthed: auth.isAuthenticated,
              onTap: auth.isAuthenticated
                  ? () {
                      _close(context);
                      context.go(AppRoutes.account);
                    }
                  : () {
                      _close(context);
                      context.push(AppRoutes.signIn);
                    },
            ),
            if (auth.isAuthenticated) const _QuickStats(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _SectionHeader(label: l10n.menuShop),
                  categories.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (items) => Column(
                      children: [
                        for (final category in items)
                          if (category.includeInMenu && category.name.isNotEmpty)
                            _CategoryNode(
                              category: category,
                              depth: 0,
                              onLeafTap: (c) {
                                _close(context);
                                context.push(
                                  AppRoutes.category(c.uid),
                                  extra: c.name,
                                );
                              },
                            ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _SectionHeader(label: l10n.menuAccountSection),
                  _DrawerTile(
                    icon: Icons.location_on_outlined,
                    label: l10n.accountAddresses,
                    onTap: () {
                      _close(context);
                      context.push(AppRoutes.addresses);
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.notifications_none,
                    label: l10n.notificationsTitle,
                    onTap: () {
                      _close(context);
                      context.push(AppRoutes.notifications);
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.help_outline,
                    label: l10n.accountHelp,
                    onTap: () {
                      _close(context);
                      context.push(AppRoutes.help);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Language toggle pinned to the bottom (Figma).
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
              child: Row(
                children: [
                  Text(
                    l10n.languageToggleLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      // White drawer in both modes → keep the label ink.
                      color: AppColors.inkHeading,
                    ),
                  ),
                  const Spacer(),
                  LanguageToggle(
                    activeLocale: store.activeLocale,
                    onChanged: (v) => ref
                        .read(storeControllerProvider.notifier)
                        .switchLocale(v),
                  ),
                ],
              ),
            ),
            if (auth.isAuthenticated)
              ListTile(
                leading: const Icon(Icons.logout, color: AppColors.brandPrimary),
                title: Text(
                  l10n.menuLogOut,
                  style: const TextStyle(
                    color: AppColors.brandPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  // Capture router before the async gap; close the drawer, sign
                  // out (revoke token + reset cache), then land on Home.
                  final router = GoRouter.of(context);
                  _close(context);
                  await ref.read(authControllerProvider.notifier).logout();
                  router.go(AppRoutes.home);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.login, color: AppColors.brandPrimary),
                title: Text(
                  l10n.welcomeSignIn,
                  style: const TextStyle(
                    color: AppColors.brandPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  _close(context);
                  context.push(AppRoutes.signIn);
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Blush profile strip: initials avatar (or person icon for guests) + name and
/// a subtitle. Tapping opens the account screen (or Sign In for guests).
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.subtitle,
    required this.avatarUrl,
    required this.isAuthed,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final String? avatarUrl;
  final bool isAuthed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: AppColors.surfaceTint,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            // Authed: the customer's photo (or initials). Guest: a person icon.
            isAuthed
                ? CustomerAvatar(
                    name: name,
                    avatarUrl: avatarUrl,
                    diameter: 52,
                    ring: true,
                    ringWidth: 1.5,
                    background: Colors.white,
                    initialsFontSize: 18,
                  )
                : Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: AppColors.brandPrimary,
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.person_outline,
                      color: AppColors.brandPrimary,
                    ),
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isAuthed && name.isNotEmpty)
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkHeading,
                      ),
                    ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isAuthed
                          ? AppColors.inkMuted
                          : AppColors.brandPrimary,
                      fontWeight: isAuthed ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!isAuthed) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    // Icon in a blush rounded-square badge (Figma).
    leading: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.brandPrimary, size: 20),
    ),
    // The drawer panel is always white (even in dark mode), so pin the label to
    // ink — the dark theme's default light-on-surface text was invisible here.
    title: Text(label, style: const TextStyle(color: AppColors.inkHeading)),
    trailing: const Icon(Icons.chevron_right, color: AppColors.inkMuted),
    onTap: onTap,
  );
}

/// A SHOP category row. Expands to reveal subcategories (and their
/// sub-subcategories) when present; a leaf navigates to its PLP. Indents by
/// [depth]; only the top level shows the blush icon badge.
class _CategoryNode extends StatelessWidget {
  const _CategoryNode({
    required this.category,
    required this.depth,
    required this.onLeafTap,
  });

  final Category category;
  final int depth;
  final void Function(Category) onLeafTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final children = category.children
        .where((c) => c.includeInMenu && c.name.isNotEmpty)
        .toList();
    final indent = 16.0 + depth * 20.0;
    final title = Text(
      category.name,
      style: TextStyle(
        fontWeight: depth == 0 ? FontWeight.w500 : FontWeight.w400,
        color: depth == 0 ? AppColors.inkHeading : AppColors.inkMuted,
        fontSize: depth == 0 ? 15 : 14,
      ),
    );
    final leading = depth == 0 ? _IconBadge(category: category) : null;

    if (children.isEmpty) {
      return ListTile(
        dense: depth > 0,
        contentPadding: EdgeInsetsDirectional.only(start: indent, end: 8),
        leading: leading,
        title: title,
        trailing: const Icon(
          Icons.chevron_right,
          color: AppColors.inkMuted,
          size: 20,
        ),
        onTap: () => onLeafTap(category),
      );
    }

    return ExpansionTile(
      tilePadding: EdgeInsetsDirectional.only(start: indent, end: 8),
      childrenPadding: EdgeInsets.zero,
      dense: depth > 0,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: leading,
      title: title,
      iconColor: AppColors.brandPrimary,
      collapsedIconColor: AppColors.inkMuted,
      children: [
        // "View All" opens the parent category's own PLP (browse everything in
        // it) — expanding alone only reveals its subcategories.
        ListTile(
          dense: true,
          contentPadding: EdgeInsetsDirectional.only(
            start: 16.0 + (depth + 1) * 20.0,
            end: 8,
          ),
          title: Text(
            l10n.menuViewAll,
            style: const TextStyle(
              fontWeight: FontWeight.w500,
              color: AppColors.brandPrimary,
              fontSize: 14,
            ),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.brandPrimary,
            size: 20,
          ),
          onTap: () => onLeafTap(category),
        ),
        for (final child in children)
          _CategoryNode(
            category: child,
            depth: depth + 1,
            onLeafTap: onLeafTap,
          ),
      ],
    );
  }
}

/// Pale navy rounded-square icon badge for a top-level SHOP category (Figma).
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(10),
    ),
    alignment: Alignment.center,
    child: Icon(
      categoryIcon(category.urlKey, category.name),
      color: AppColors.brandPrimary,
      size: 20,
    ),
  );
}

/// Three quick-stat tiles (Orders / Wishlist / Vouchers) — Figma. Counts are
/// bound to real data where the backend exposes it; Vouchers has no source yet
/// (shows 0 until a backend field is wired).
class _QuickStats extends ConsumerWidget {
  const _QuickStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final orders = ref
        .watch(customerOrderCountProvider)
        .maybeWhen(data: (n) => n, orElse: () => 0);
    final wishlist = ref.watch(wishlistControllerProvider).entries.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _StatTile(
            icon: Icons.shopping_bag_outlined,
            count: orders,
            label: l10n.accountOrders,
            onTap: () {
              Navigator.of(context).maybePop();
              context.push(AppRoutes.orders);
            },
          ),
          const SizedBox(width: 12),
          _StatTile(
            icon: Icons.favorite_border,
            count: wishlist,
            label: l10n.navWishlist,
            onTap: () {
              Navigator.of(context).maybePop();
              context.go(AppRoutes.wishlist);
            },
          ),
          const SizedBox(width: 12),
          _StatTile(
            icon: Icons.confirmation_number_outlined,
            count: 0,
            label: l10n.drawerVouchers,
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.count,
    required this.label,
    this.onTap,
  });
  final IconData icon;
  final int count;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.brandPrimary, size: 20),
              const SizedBox(height: 6),
              Text(
                '$count',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: AppColors.inkHeading,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: AppColors.inkMuted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1,
      ),
    ),
  );
}
