import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../data/notification_inbox.dart';
import '../domain/notification_item.dart';

/// App-bar bell that opens the notification feed, with the Figma unread dot
/// (07 Home "icon-btn/bell"): an orange dot on its top corner while the local
/// inbox holds anything unread; the tooltip says how many. [color] overrides
/// the icon colour for app bars that don't theme their actions (e.g. the navy
/// Home header).
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    this.color,
    this.icon = Icons.notifications_none,
  });

  final Color? color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<List<NotificationItem>>(
      valueListenable: NotificationInbox.instance.items,
      builder: (context, items, _) {
        final unread = items.where((i) => !i.read).length;
        return IconButton(
          tooltip: unread > 0
              ? l10n.notificationsUnread(unread)
              : l10n.notificationsTitle,
          onPressed: () => context.push(AppRoutes.notifications),
          icon: Badge(
            isLabelVisible: unread > 0,
            smallSize: 9,
            backgroundColor: AppColors.accent,
            child: Icon(icon, color: color),
          ),
        );
      },
    );
  }
}
