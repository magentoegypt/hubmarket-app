import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import 'notification_settings_controller.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final promoEnabled = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationsTitle)),
      body: ListView(
        children: [
          SwitchListTile.adaptive(
            value: promoEnabled,
            onChanged: (v) => ref
                .read(notificationSettingsProvider.notifier)
                .setPromotions(v),
            title: Text(l10n.notificationsPromoTitle),
            subtitle: Text(l10n.notificationsPromoBody),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              l10n.notificationsOrdersNote,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ),
        ],
      ),
    );
  }
}
