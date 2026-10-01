import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/notifications/presentation/notifications_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';

/// The feed of Figma 20g: filter chips, Today / Earlier, the 30-day footer.

final en = lookupAppLocalizations(const Locale('en'));

NotificationItem _item(
  String id,
  String title,
  NotificationKind kind, {
  Duration ago = const Duration(minutes: 5),
  bool read = false,
  String body = '',
}) => NotificationItem(
  id: id,
  kind: kind,
  title: title,
  body: body,
  receivedAt: DateTime.now().subtract(ago),
  read: read,
);

Future<void> _pump(WidgetTester tester, List<NotificationItem> items) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  NotificationInbox.instance.items.value = items;
  addTearDown(() => NotificationInbox.instance.items.value = const []);
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    routes: [
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notificationSettings,
        builder: (_, __) => const Scaffold(body: Text('SETTINGS')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
  router.push(AppRoutes.notifications);
  await tester.pumpAndSettle();
}

/// Taps a chip; without the app's fonts (Ahem, one em per letter) the row is
/// wider than the screen, so it is scrolled into view first.
Future<void> _tapChip(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('the kind a push belongs to', () {
    NotificationKind kind(String type) =>
        NotificationItem.kindFrom({'type': type});

    test('a return or a refund is a return, even from an order', () {
      expect(kind('return_update'), NotificationKind.returns);
      expect(kind('refund_issued'), NotificationKind.returns);
      expect(kind('rma_reply'), NotificationKind.returns);
      expect(kind('return_order'), NotificationKind.returns);
    });

    test('store credit and the rest keep their kinds', () {
      expect(kind('store_credit'), NotificationKind.credit);
      expect(kind('order_shipped'), NotificationKind.order);
      expect(kind('delivered'), NotificationKind.delivered);
      expect(kind('price_drop'), NotificationKind.wishlist);
      expect(kind('flash_sale'), NotificationKind.promo);
      expect(kind('hello'), NotificationKind.general);
    });
  });

  group('the inbox keeps 30 days', () {
    test('withinRetention drops what is older', () {
      final now = DateTime(2026, 10, 1, 12);
      NotificationItem at(String id, Duration ago) => NotificationItem(
        id: id,
        kind: NotificationKind.order,
        title: id,
        body: '',
        receivedAt: now.subtract(ago),
      );
      final kept = NotificationInbox.withinRetention([
        at('fresh', const Duration(hours: 1)),
        at('edge', const Duration(days: 30)),
        at('old', const Duration(days: 30, minutes: 1)),
      ], now: now);
      // Exactly 30 days old is still kept.
      expect(kept.map((i) => i.id), ['fresh', 'edge']);
    });

    test('a new push drops the old ones with it', () {
      final inbox = NotificationInbox.instance;
      addTearDown(inbox.clear);
      inbox.items.value = [
        _item('old', 'old', NotificationKind.order, ago: const Duration(days: 45)),
        _item('recent', 'recent', NotificationKind.order, ago: const Duration(days: 3)),
      ];
      inbox.add(_item('new', 'new', NotificationKind.order));
      expect(inbox.items.value.map((i) => i.id), ['new', 'recent']);
    });

    test('what is read back from the cache is pruned too', () async {
      final inbox = NotificationInbox.instance;
      addTearDown(inbox.clear);
      final cache = FakeLocalCache();
      final stored = [
        _item('old', 'old', NotificationKind.order, ago: const Duration(days: 31)),
        _item('recent', 'recent', NotificationKind.order, ago: const Duration(days: 29)),
      ];
      cache.writeString(
        'notification_inbox',
        '[${stored.map((i) => _json(i)).join(',')}]',
      );
      await inbox.init(cache);
      expect(inbox.items.value.map((i) => i.id), ['recent']);
    });
  });

  testWidgets('today and earlier, with the footer', (tester) async {
    await _pump(tester, [
      _item('a', 'Out for delivery', NotificationKind.order),
      _item(
        'b',
        'Price drop on your wishlist',
        NotificationKind.wishlist,
        ago: const Duration(days: 3),
        read: true,
      ),
    ]);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('EARLIER'), findsOneWidget);
    expect(find.text(en.notificationsKeptNote), findsOneWidget);
    // Today's row shows its clock time, an older one its date.
    final now = DateTime.now();
    final hh = now.subtract(const Duration(minutes: 5));
    expect(
      find.text(
        '${hh.hour.toString().padLeft(2, '0')}:'
        '${hh.minute.toString().padLeft(2, '0')}',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the chips filter the feed', (tester) async {
    await _pump(tester, [
      _item('a', 'Out for delivery', NotificationKind.order),
      _item('b', 'Return approved', NotificationKind.returns),
      _item('c', 'Weekend sale', NotificationKind.promo),
      _item('d', 'Price drop', NotificationKind.wishlist),
      _item('e', 'Welcome', NotificationKind.welcome),
    ]);
    expect(find.text('Out for delivery'), findsOneWidget);
    expect(find.text('Welcome'), findsOneWidget);

    await _tapChip(tester, en.notificationsFilterOrders);
    expect(find.text('Out for delivery'), findsOneWidget);
    expect(find.text('Return approved'), findsNothing);

    await _tapChip(tester, en.notificationsFilterReturns);
    expect(find.text('Return approved'), findsOneWidget);
    expect(find.text('Out for delivery'), findsNothing);

    await _tapChip(tester, en.notificationsFilterOffers);
    expect(find.text('Weekend sale'), findsOneWidget);
    expect(find.text('Price drop'), findsOneWidget);
    expect(find.text('Welcome'), findsNothing);

    // A welcome note belongs to no family: only All shows it.
    await _tapChip(tester, en.notificationsFilterAll);
    expect(find.text('Welcome'), findsOneWidget);
  });

  testWidgets('a family with nothing in it says so', (tester) async {
    await _pump(tester, [
      _item('a', 'Out for delivery', NotificationKind.order),
    ]);
    await _tapChip(tester, en.notificationsFilterReturns);
    expect(find.text(en.notificationsFilterEmpty), findsOneWidget);
    // The 30-day note still closes the page.
    expect(find.text(en.notificationsKeptNote), findsOneWidget);
  });

  testWidgets('Mark all as read stays while anything is unread', (
    tester,
  ) async {
    await _pump(tester, [
      _item('a', 'Out for delivery', NotificationKind.order),
      _item('b', 'Return approved', NotificationKind.returns, read: true),
    ]);
    await tester.tap(find.text(en.notificationsMarkAllRead));
    await tester.pumpAndSettle();
    expect(NotificationInbox.instance.unreadCount, 0);
    expect(find.text(en.notificationsMarkAllRead), findsNothing);
  });

  testWidgets('the gear opens Notification settings', (tester) async {
    await _pump(tester, [_item('a', 'Out for delivery', NotificationKind.order)]);
    await tester.tap(find.byTooltip(en.notificationSettingsTitle));
    await tester.pumpAndSettle();
    expect(find.text('SETTINGS'), findsOneWidget);
  });

  testWidgets('an empty inbox keeps its own page', (tester) async {
    await _pump(tester, const []);
    expect(find.text(en.notificationsEmptyTitle), findsOneWidget);
    expect(find.text(en.notificationsFilterAll), findsNothing);
  });
}

String _json(NotificationItem item) =>
    '{"id":"${item.id}","kind":"${item.kind.name}","title":"${item.title}",'
    '"body":"","receivedAt":"${item.receivedAt.toIso8601String()}",'
    '"read":${item.read}}';
