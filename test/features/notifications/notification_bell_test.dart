import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';
import 'package:hubmarket_app/features/notifications/data/notification_inbox.dart';
import 'package:hubmarket_app/features/notifications/domain/notification_item.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_bell.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

NotificationItem _item(String id, {bool read = false}) => NotificationItem(
  id: id,
  kind: NotificationKind.order,
  title: 'Order #000000248 shipped',
  body: 'Your package is on its way.',
  receivedAt: DateTime.now().subtract(const Duration(minutes: 5)),
  read: read,
);

/// An app bar with the bell, as [HubAppBar] has it.
Widget _app({String locale = 'en'}) {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(
        path: '/screen',
        builder: (_, __) => Scaffold(
          appBar: AppBar(actions: const [NotificationBell()]),
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (_, __) => const Scaffold(body: Text('feed')),
      ),
    ],
  );
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      theme: AppTheme.light(locale),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

Finder get _dot =>
    find.byWidgetPredicate((w) => w is Badge && w.isLabelVisible);

void main() {
  tearDown(() => NotificationInbox.instance.items.value = const []);

  testWidgets('an orange dot while anything is unread', (tester) async {
    NotificationInbox.instance.items.value = [
      _item('a'),
      _item('b'),
      _item('c', read: true),
    ];
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(_dot, findsOneWidget);
    final badge = tester.widget<Badge>(_dot);
    expect(badge.backgroundColor, AppColors.accent);
    // A dot (Figma 07 "unread"), not a count.
    expect(badge.label, isNull);
    expect(find.byTooltip('Notifications, 2 unread'), findsOneWidget);
  });

  testWidgets('no dot once everything is read', (tester) async {
    NotificationInbox.instance.items.value = [_item('a')];
    await tester.pumpWidget(_app());
    await tester.pump();
    expect(_dot, findsOneWidget);

    NotificationInbox.instance.markAllRead();
    await tester.pump();
    expect(_dot, findsNothing);
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('the tooltip counts in Arabic', (tester) async {
    NotificationInbox.instance.items.value = [_item('a')];
    await tester.pumpWidget(_app(locale: 'ar'));
    await tester.pump();
    expect(
      find.byTooltip(
        lookupAppLocalizations(const Locale('ar')).notificationsUnread(1),
      ),
      findsOneWidget,
    );
  });

  testWidgets('opens the feed', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    await tester.tap(find.byType(NotificationBell));
    await tester.pumpAndSettle();
    expect(find.text('feed'), findsOneWidget);
  });
}
