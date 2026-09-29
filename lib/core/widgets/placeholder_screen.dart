import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../app/shell/hub_scaffold.dart';
import '../../app/theme/app_colors.dart';
import '../../l10n/l10n.dart';

/// A "coming soon" placeholder for destinations that land in later phases.
/// When [tab] is set it keeps the bottom nav (cart/wishlist/account tabs);
/// otherwise it's a plain pushed screen (e.g. search).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.tab});

  final String title;
  final AppTab? tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final body = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome_outlined,
              size: 48,
              color: AppColors.inkMuted,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.comingSoon,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.comingSoonBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );

    final currentTab = tab;
    if (currentTab != null) {
      return HubScaffold(currentTab: currentTab, body: body);
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}
