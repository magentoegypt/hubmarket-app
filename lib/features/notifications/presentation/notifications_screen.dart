import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/notification_routes.dart';
import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/hub_icons.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/widgets/grouped_list.dart';
import '../../../core/widgets/hub_chip.dart';
import '../../../core/widgets/hub_icon_button.dart';
import '../../../core/widgets/network_image.dart';
import '../../../l10n/l10n.dart';
import '../data/notification_inbox.dart';
import '../domain/notification_item.dart';

/// What a filter chip shows (Figma 20g `filters`): every notification, or one
/// family of them.
enum _Filter {
  all,
  orders,
  returns,
  offers;

  bool matches(NotificationKind kind) => switch (this) {
    _Filter.all => true,
    _Filter.orders =>
      kind == NotificationKind.order || kind == NotificationKind.delivered,
    _Filter.returns => kind == NotificationKind.returns,
    _Filter.offers =>
      kind == NotificationKind.promo || kind == NotificationKind.wishlist,
  };

  String label(AppLocalizations l10n) => switch (this) {
    _Filter.all => l10n.notificationsFilterAll,
    _Filter.orders => l10n.notificationsFilterOrders,
    _Filter.returns => l10n.notificationsFilterReturns,
    _Filter.offers => l10n.notificationsFilterOffers,
  };
}

/// Notification feed (Figma 20g): the pushes received on this device, newest
/// first, under filter chips (All, Orders, Returns, Offers) and split into Today
/// and Earlier — unread rows are blush with an orange dot — backed by the local
/// inbox. Tapping a row opens what the push points at, as tapping the push
/// itself does ([notificationRoute]), and marks it read; the gear opens
/// Notification settings. The inbox keeps 30 days
/// ([NotificationInbox.retention]) and the footer says so.
///
/// "Mark all as read" has no place in the frame; it sits at the end of the
/// first group's header while anything is unread. A push shows a thumbnail when
/// its payload carries an `image` URL.
class NotificationsScreen extends ConsumerStatefulWidget {
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
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(notificationInboxProvider);

    return Scaffold(
      appBar: subpageAppBar(
        context,
        l10n.notificationsTitle,
        divider: true,
        actions: [
          HubIconButton(
            icon: HubIcons.settings,
            tooltip: l10n.notificationSettingsTitle,
            onPressed: () => context.push(AppRoutes.notificationSettings),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<NotificationItem>>(
        valueListenable: inbox.items,
        builder: (context, items, _) {
          if (items.isEmpty) return const _EmptyNotifications();
          final now = DateTime.now();
          final shown = [
            for (final item in items)
              if (_filter.matches(item.kind)) item,
          ];
          final today = [
            for (final item in shown)
              if (_sameDay(item.receivedAt, now)) item,
          ];
          final earlier = [
            for (final item in shown)
              if (!_sameDay(item.receivedAt, now)) item,
          ];
          final hasUnread = items.any((i) => !i.read);
          Widget row(NotificationItem item) => _NotificationTile(
            item: item,
            now: now,
            onTap: () => NotificationsScreen._open(context, inbox, item),
          );
          return Column(
            children: [
              _Filters(
                selected: _filter,
                onSelect: (filter) => setState(() => _filter = filter),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    if (today.isNotEmpty) ...[
                      _GroupHeader(
                        l10n.notificationsToday,
                        trailing: hasUnread
                            ? _MarkAllRead(onTap: inbox.markAllRead)
                            : null,
                      ),
                      for (final item in today) row(item),
                    ],
                    if (earlier.isNotEmpty) ...[
                      _GroupHeader(
                        l10n.notificationsEarlier,
                        trailing: hasUnread && today.isEmpty
                            ? _MarkAllRead(onTap: inbox.markAllRead)
                            : null,
                      ),
                      for (final item in earlier) row(item),
                    ],
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.notificationsFilterEmpty,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.of(
                            context,
                          ).body.copyWith(color: context.scaffoldMuted),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        l10n.notificationsKeptNote,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.of(
                          context,
                        ).caption.copyWith(color: context.scaffoldMuted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The chips under the bar: 12 above, 4 below, 8 apart.
class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelect});

  final _Filter selected;
  final ValueChanged<_Filter> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          for (final filter in _Filter.values) ...[
            if (filter != _Filter.values.first) const SizedBox(width: 8),
            HubChip(
              label: filter.label(l10n),
              selected: filter == selected,
              onTap: () => onSelect(filter),
            ),
          ],
        ],
      ),
    );
  }
}

/// "TODAY" / "EARLIER": EN/Caption Strong, muted, 16 at the sides, 14 above and
/// 6 below.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.label, {this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: AppTextStyles.of(
              context,
            ).captionStrong.copyWith(color: context.scaffoldMuted),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

class _MarkAllRead extends StatelessWidget {
  const _MarkAllRead({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Text(
      AppLocalizations.of(context).notificationsMarkAllRead,
      style: AppTextStyles.of(context).captionStrong.copyWith(
        color: context.isDarkMode ? Colors.white : AppColors.accentStrong,
      ),
    ),
  );
}

/// One notification (Figma `notification`): a 40 px tinted disc for its kind,
/// the title with its time, the text, then a photo when it has one and the dot
/// while it is unread; 16 / 14 px of padding, 12 between the parts, a hairline
/// under it.
class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.now,
    required this.onTap,
  });

  final NotificationItem item;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final unread = !item.read;
    final style = _styleOf(item.kind);
    final image = _imageOf(item);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            // Read rows show the scaffold (white, or dark in dark mode).
            color: unread
                ? (context.isDarkMode ? Colors.white10 : AppColors.accentSubtle)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: style.fill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(style.icon, size: 20, color: style.color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: t.bodyStrong.copyWith(
                                color: context.scaffoldHeading,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _timeLabel(context, item.receivedAt, now),
                            style: t.micro.copyWith(
                              color: context.scaffoldMuted,
                            ),
                          ),
                        ],
                      ),
                      if (item.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.body,
                          style: t.caption.copyWith(
                            color: context.isDarkMode
                                ? context.scaffoldMuted
                                : AppColors.inkSubtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (image != null) ...[
                  const SizedBox(width: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: HubImage(
                        url: image,
                        decodeWidth: 48,
                        placeholder: (_) =>
                            const ColoredBox(color: AppColors.surfaceSubtle),
                        error: (_) =>
                            const ColoredBox(color: AppColors.surfaceSubtle),
                      ),
                    ),
                  ),
                ],
                if (unread) ...[
                  const SizedBox(width: 12),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? Colors.white
                          : AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: context.isDarkMode ? Colors.white12 : AppColors.borderSubtle,
        ),
      ],
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
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
                HubIcons.bell,
                size: 48,
                color: AppColors.brandPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.notificationsEmptyTitle,
              style: t.heading2.copyWith(color: context.scaffoldHeading),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.notificationsEmptyBody,
              textAlign: TextAlign.center,
              style: t.body.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The disc's icon and tints per kind — the frame's own: a truck on green for
/// an order, a return's arrow on blue, a tag on red for a price drop, a gift on
/// green for credit, a clock on amber for an offer.
({IconData icon, Color color, Color fill}) _styleOf(NotificationKind kind) =>
    switch (kind) {
      NotificationKind.order => (
        icon: HubIcons.truck,
        color: AppColors.successStrong,
        fill: AppColors.successSubtle,
      ),
      NotificationKind.delivered => (
        icon: HubIcons.circleCheck,
        color: AppColors.successStrong,
        fill: AppColors.successSubtle,
      ),
      NotificationKind.returns => (
        icon: HubIcons.rotateCcw,
        color: AppColors.info,
        fill: AppColors.infoSubtle,
      ),
      NotificationKind.credit => (
        icon: HubIcons.gift,
        color: AppColors.successStrong,
        fill: AppColors.successSubtle,
      ),
      NotificationKind.wishlist => (
        icon: HubIcons.tag,
        color: AppColors.danger,
        fill: AppColors.dangerSurface,
      ),
      NotificationKind.promo => (
        icon: HubIcons.clock,
        color: AppColors.warning,
        fill: AppColors.warningSubtle,
      ),
      NotificationKind.welcome => (
        icon: HubIcons.partyPopper,
        color: AppColors.accentStrong,
        fill: AppColors.accentSubtle,
      ),
      NotificationKind.general => (
        icon: HubIcons.bell,
        color: AppColors.inkSubtle,
        fill: AppColors.surfaceTint,
      ),
    };

/// A thumbnail URL the push carries (`image`, or `image_url`), if any.
String? _imageOf(NotificationItem item) {
  for (final key in const ['image', 'image_url']) {
    final value = item.data[key];
    if (value is String && value.trim().startsWith('http')) {
      return value.trim();
    }
  }
  return null;
}

/// The time on a row, as the frame prints it: the clock time for today
/// ("08:30"), "Yesterday", then the date ("26 Sep"). Digits stay Western.
String _timeLabel(BuildContext context, DateTime time, DateTime now) {
  final l10n = AppLocalizations.of(context);
  final locale = Localizations.localeOf(context).languageCode;
  if (_sameDay(time, now)) return DateFormat('HH:mm').format(time);
  if (_sameDay(time, now.subtract(const Duration(days: 1)))) {
    return l10n.notifYesterday;
  }
  try {
    return DateFormat('d MMM', locale).format(time);
  } catch (_) {
    return DateFormat('d MMM').format(time);
  }
}
