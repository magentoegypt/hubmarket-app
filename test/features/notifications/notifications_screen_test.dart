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

NotificationItem _item(String id, String title, Map<String, dynamic> data) =>
    NotificationItem(
      id: id,
      kind: NotificationItem.kindFrom(data),
      title: title,
      body: '',
      receivedAt: DateTime.now(),
      data: data,
    );

/// The feed over stand-ins for the screens a push can open.
Future<void> _pump(WidgetTester tester, List<NotificationItem> items) async {
  final inbox = NotificationInbox.instance..clear();
  for (final item in items.reversed) {
    inbox.add(item);
  }
  addTearDown(inbox.clear);
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
        path: AppRoutes.cart,
        builder: (_, __) => const Scaffold(body: Text('CART')),
      ),
      GoRoute(
        path: '/product/:urlKey',
        builder: (_, state) => Scaffold(
          appBar: AppBar(),
          body: Text('PDP ${state.pathParameters['urlKey']}'),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.orders}/:number',
        builder: (_, state) =>
            Scaffold(body: Text('ORDER ${state.pathParameters['number']}')),
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

bool _read(String id) =>
    NotificationInbox.instance.items.value.firstWhere((i) => i.id == id).read;

void main() {
  testWidgets('a row opens its target over the feed, then reads as read', (
    tester,
  ) async {
    await _pump(tester, [
      _item('p1', 'Price drop on Coco', {'type': 'product', 'id': 'coco'}),
    ]);
    expect(_read('p1'), isFalse);

    await tester.tap(find.text('Price drop on Coco'));
    await tester.pumpAndSettle();

    expect(find.text('PDP coco'), findsOneWidget);
    expect(_read('p1'), isTrue);

    // Back returns to the feed.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Price drop on Coco'), findsOneWidget);
  });

  testWidgets('an order update opens that order', (tester) async {
    await _pump(tester, [
      _item('o1', 'Your order has shipped', {
        'type': 'order',
        'id': '000000248',
      }),
    ]);

    await tester.tap(find.text('Your order has shipped'));
    await tester.pumpAndSettle();

    expect(find.text('ORDER 000000248'), findsOneWidget);
    expect(_read('o1'), isTrue);
  });

  testWidgets('a tab target is switched to', (tester) async {
    await _pump(tester, [
      _item('c1', 'Still in your cart', {'type': 'cart'}),
    ]);

    await tester.tap(find.text('Still in your cart'));
    await tester.pumpAndSettle();

    expect(find.text('CART'), findsOneWidget);
    expect(_read('c1'), isTrue);
  });

  testWidgets('a push without a target is only marked read', (tester) async {
    await _pump(tester, [
      _item('g1', 'Welcome to Hub Market', {'type': 'welcome'}),
    ]);

    await tester.tap(find.text('Welcome to Hub Market'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsOneWidget);
    expect(_read('g1'), isTrue);
  });
}
