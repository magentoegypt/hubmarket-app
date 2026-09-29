import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/hub_back_button.dart';
import '../../features/notifications/presentation/notification_bell.dart';
import '../routes.dart';

/// Decluttered app bar per the design review: Z-mark + `HUB MARKET` logo lockup,
/// no cart icon. Because [HubScaffold] always attaches a drawer, the
/// AppBar's auto-leading would show the hamburger even on pushed routes — so the
/// leading is chosen explicitly: a back button on a pushed route, and the drawer
/// hamburger (leading: null → auto) on a tab root.
///
/// The lockup sits against the leading edge rather than centred (CL042-DEV16),
/// matching the storefront header. `centerTitle: false` resolves through
/// [Directionality], so it lands beside the hamburger in both directions: to
/// its right in English, to its left in Arabic.
class HubAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HubAppBar({super.key, this.showSearch = true});

  final bool showSearch;

  // Slightly taller than the Material default to seat the vertical lockup
  // (Z-mark over wordmark), matching the Figma 52 px header.
  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    // Pushed route → back button; tab root → null so the drawer hamburger shows.
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return AppBar(
      toolbarHeight: 60,
      centerTitle: false,
      // The AppBar reserves a wide gap after the leading widget for text
      // titles; the logo should sit right next to it.
      titleSpacing: 4,
      leading: canPop ? const HubBackButton() : null,
      title: const BrandLogo(height: 44),
      actions: [
        if (showSearch)
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push(AppRoutes.search),
          ),
        const NotificationBell(),
      ],
    );
  }
}
