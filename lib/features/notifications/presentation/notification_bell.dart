import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/widgets/hub_icon_button.dart';
import '../../../l10n/l10n.dart';
import '../data/notification_inbox.dart';
import '../domain/notification_item.dart';
import '../../../app/theme/hub_icons.dart';

/// App-bar bell that opens the notification feed (Figma "icon-btn/bell"): a
/// 40 px [HubIconButton] with the orange unread dot on its top corner (07
/// Home "unread") while the local inbox holds anything unread; the tooltip says
/// how many. [color] overrides the icon colour for bars that don't theme their
/// actions (the navy Home header), and [dotBorderColor] rings the dot in that
/// bar's colour so it reads on top of the bell.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    this.color,
    this.icon = HubIcons.bell,
    this.dotBorderColor,
  });

  final Color? color;
  final IconData icon;
  final Color? dotBorderColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<List<NotificationItem>>(
      valueListenable: NotificationInbox.instance.items,
      builder: (context, items, _) {
        final unread = items.where((i) => !i.read).length;
        return HubIconButton(
          icon: icon,
          color: color,
          tooltip: unread > 0
              ? l10n.notificationsUnread(unread)
              : l10n.notificationsTitle,
          onPressed: () => context.push(AppRoutes.notifications),
          showDot: unread > 0,
          dotBorderColor: dotBorderColor,
        );
      },
    );
  }
}
