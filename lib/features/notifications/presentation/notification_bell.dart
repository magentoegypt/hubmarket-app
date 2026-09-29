import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../l10n/l10n.dart';
import '../data/notification_inbox.dart';
import '../domain/notification_item.dart';

/// App-bar bell that opens the notification feed, with a live unread badge
/// driven by the local inbox. [color] overrides the icon colour for app bars
/// that don't theme their actions (e.g. the home header).
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<List<NotificationItem>>(
      valueListenable: NotificationInbox.instance.items,
      builder: (context, items, _) {
        final unread = items.where((i) => !i.read).length;
        return IconButton(
          tooltip: l10n.notificationsTitle,
          onPressed: () => context.push(AppRoutes.notifications),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(Icons.notifications_none, color: color),
          ),
        );
      },
    );
  }
}
