import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/notification_routes.dart';
import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/hub_back_button.dart';
import '../../../l10n/l10n.dart';
import '../data/notification_inbox.dart';
import '../domain/notification_item.dart';

/// Notification feed (Figma 65:53): a list of received pushes — unread rows are
/// pale navy with a navy dot — plus "Mark all as read", backed by the local
/// inbox. Tapping a row opens what the push points at, as tapping the push
/// itself does ([notificationRoute]), and marks it read. Notification
/// *preferences* live in Settings.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  /// Opens [item]'s target — a tab is switched to, anything else opens over
  /// the feed so Back comes back here — then marks it read. A push without a
  /// target is only marked read.
  static void _open(
    BuildContext context,
    NotificationInbox inbox,
    NotificationItem item,
  ) {
    final route = notificationRoute(item.data);
    if (route != null) {
      if (AppTab.values.any((tab) => tab.route == route)) {
        context.go(route);
      } else {
        context.push(route);
      }
    }
    inbox.markRead(item.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(notificationInboxProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const HubBackButton(),
        title: Text(l10n.notificationsTitle),
      ),
      body: ValueListenableBuilder<List<NotificationItem>>(
        valueListenable: inbox.items,
        builder: (context, items, _) {
          if (items.isEmpty) return _EmptyNotifications();
          final hasUnread = items.any((i) => !i.read);
          return Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: InkWell(
                      onTap: hasUnread ? inbox.markAllRead : null,
                      child: Text(
                        l10n.notificationsMarkAllRead,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: hasUnread
                              ? AppColors.brandPrimary
                              : AppColors.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderDefault,
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderDefault,
                  ),
                  itemBuilder: (context, i) => _NotificationTile(
                    item: items[i],
                    onTap: () => _open(context, inbox, items[i]),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final NotificationItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !item.read;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread ? AppColors.surfaceTint : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: unread ? Colors.white : AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _iconFor(item.kind),
                size: 20,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.inkHeading,
                    ),
                  ),
                  if (item.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      item.body,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    _relativeTime(context, item.receivedAt),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppColors.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsetsDirectional.only(start: 8, top: 5),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.brandPrimary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.surfaceTint,
              child: Icon(
                Icons.notifications_none,
                size: 48,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.notificationsEmptyTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.notificationsEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(NotificationKind kind) => switch (kind) {
  NotificationKind.order => Icons.local_shipping_outlined,
  NotificationKind.promo => Icons.local_offer_outlined,
  NotificationKind.wishlist => Icons.favorite_border,
  NotificationKind.delivered => Icons.check_circle_outline,
  NotificationKind.welcome => Icons.celebration_outlined,
  NotificationKind.general => Icons.notifications_none,
};

String _relativeTime(BuildContext context, DateTime time) {
  final l10n = AppLocalizations.of(context);
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return l10n.notifJustNow;
  if (diff.inMinutes < 60) return l10n.notifMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.notifHoursAgo(diff.inHours);
  if (diff.inDays <= 1) return l10n.notifYesterday;
  return l10n.notifDaysAgo(diff.inDays);
}
