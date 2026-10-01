import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/config/store_features.dart';
import 'package:hubmarket_app/core/config/store_timezone.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/order_cancellation.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_detail_screen.dart';
import 'package:hubmarket_app/features/account/presentation/screens/order_tracking_screen.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';

/// The live store's reasons (storeConfig, 29 Sep 2026).
const _reasons = [
  'The item(s) are no longer needed',
  'The order was placed by mistake',
  'Item(s) not arriving within the expected timeframe',
  'Found a better price elsewhere',
  'Other',
];

const _enabled = StoreFeatures(
  orderCancellationEnabled: true,
  cancellationReasons: _reasons,
);

const _open = CustomerOrder(
  number: '000000123',
  status: 'Pending',
  date: '2026-09-28 10:42:00',
  id: 'MTIz',
  token: 'tok-123',
  availableActions: {'CANCEL', 'REORDER'},
);

const _cancelled = CustomerOrder(
  number: '000000123',
  status: 'Canceled',
  date: '2026-09-28 10:42:00',
  id: 'MTIz',
  availableActions: {'REORDER'},
);

const _guestOrder = CustomerOrder(
  number: '000000124',
  status: 'Pending',
  date: '2026-09-28 11:00:00',
  id: 'MTI0',
  token: 'tok-124',
  availableActions: {'CANCEL'},
  placedAsGuest: true,
);

Future<void> _pump(
  WidgetTester tester, {
  required Widget screen,
  StoreFeatures features = _enabled,
  FakeAccountRepository? account,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(path: '/screen', builder: (_, __) => screen),
      for (final p in [
        AppRoutes.home,
        AppRoutes.categories,
        AppRoutes.cart,
        AppRoutes.wishlist,
        AppRoutes.account,
        AppRoutes.help,
      ])
        GoRoute(path: p, builder: (_, __) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localCacheProvider.overrideWithValue(FakeLocalCache()),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs(locale)),
        secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
        storeTimezoneProvider.overrideWith((ref) async => 'Asia/Dubai'),
        storeFeaturesProvider.overrideWith((ref) async => features),
        accountRepositoryProvider.overrideWithValue(
          account ?? FakeAccountRepository(),
        ),
        // Build 1: no Hub Market App, so no store-credit lookup and no Return
        // items (see the returns tests).
        hubAppOverride(const HubAppState.unavailable()),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: Locale(locale),
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
  await tester.pumpAndSettle();
}

Finder _sheetConfirm(AppLocalizations l10n) => find.descendant(
  of: find.byType(BottomSheet),
  matching: find.text(l10n.orderCancelAction),
);

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('offersOrderCancel', () {
    test('needs the store switch, a reason and CANCEL on the order', () {
      expect(offersOrderCancel(_enabled, _open), isTrue);
      expect(offersOrderCancel(StoreFeatures.none, _open), isFalse);
      expect(
        offersOrderCancel(
          const StoreFeatures(orderCancellationEnabled: true),
          _open,
        ),
        isFalse,
        reason: 'cancelOrder only accepts one of the configured reasons',
      );
      expect(offersOrderCancel(_enabled, _cancelled), isFalse);
    });

    test('needs the id for a customer and the token for a guest', () {
      const noId = CustomerOrder(
        number: '1',
        status: 'Pending',
        date: '',
        availableActions: {'CANCEL'},
      );
      expect(offersOrderCancel(_enabled, noId), isFalse);
      const guestNoToken = CustomerOrder(
        number: '2',
        status: 'Pending',
        date: '',
        id: 'Mg==',
        availableActions: {'CANCEL'},
        placedAsGuest: true,
      );
      expect(offersOrderCancel(_enabled, guestNoToken), isFalse);
      expect(offersOrderCancel(_enabled, _guestOrder), isTrue);
    });
  });

  group('order detail', () {
    testWidgets('no button while the store has cancellation off', (
      tester,
    ) async {
      await _pump(
        tester,
        screen: const OrderDetailScreen(order: _open),
        features: const StoreFeatures(cancellationReasons: _reasons),
      );
      expect(find.text(en.orderCancelAction), findsNothing);
    });

    testWidgets('cancels with the chosen reason and shows the result', (
      tester,
    ) async {
      final account = FakeAccountRepository(cancelledOrder: _cancelled);
      await _pump(
        tester,
        screen: const OrderDetailScreen(order: _open),
        account: account,
      );
      expect(find.text(en.orderCancelHint), findsOneWidget);

      await tester.tap(find.text(en.orderCancelAction));
      await tester.pumpAndSettle();
      expect(find.text(en.orderCancelTitle('000000123')), findsOneWidget);
      expect(find.text(en.orderCancelReasonTitle), findsOneWidget);
      for (final reason in _reasons) {
        expect(find.text(reason), findsOneWidget);
      }

      await tester.tap(find.text(_reasons[1]));
      await tester.pumpAndSettle();
      await tester.tap(_sheetConfirm(en));
      await tester.pumpAndSettle();

      expect(account.cancelCalls, [
        (orderId: 'MTIz', reason: 'The order was placed by mistake'),
      ]);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text(en.orderCancelDone), findsOneWidget);
      // Magento's updated order replaces the shown one: its status pill (in
      // capitals, Figma 22) says so and no CANCEL is offered any more.
      expect(find.text('CANCELED'), findsOneWidget);
      expect(find.text(en.orderCancelAction), findsNothing);
    });

    testWidgets('Keep my order changes nothing', (tester) async {
      final account = FakeAccountRepository(cancelledOrder: _cancelled);
      await _pump(
        tester,
        screen: const OrderDetailScreen(order: _open),
        account: account,
      );
      await tester.tap(find.text(en.orderCancelAction));
      await tester.pumpAndSettle();
      await tester.tap(find.text(en.orderCancelKeep));
      await tester.pumpAndSettle();
      expect(account.cancelCalls, isEmpty);
      expect(find.text(en.orderCancelAction), findsOneWidget);
    });

    testWidgets('a refusal shows the store message and keeps the sheet', (
      tester,
    ) async {
      const refusal = 'Order with one or more items shipped cannot be cancelled';
      await _pump(
        tester,
        screen: const OrderDetailScreen(order: _open),
        account: FakeAccountRepository(cancelError: refusal),
      );
      await tester.tap(find.text(en.orderCancelAction));
      await tester.pumpAndSettle();
      await tester.tap(_sheetConfirm(en));
      await tester.pumpAndSettle();
      expect(find.text(refusal), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('guest order (track order)', () {
    testWidgets('requests cancellation by e-mail with the order token', (
      tester,
    ) async {
      final account = FakeAccountRepository();
      await _pump(
        tester,
        screen: const OrderTrackingScreen(order: _guestOrder),
        account: account,
      );
      await tester.ensureVisible(find.text(en.orderCancelAction));
      await tester.tap(find.text(en.orderCancelAction));
      await tester.pumpAndSettle();
      // The sheet says what happens next for a guest.
      expect(find.textContaining(en.orderCancelGuestNote), findsOneWidget);

      await tester.tap(_sheetConfirm(en));
      await tester.pumpAndSettle();
      expect(account.guestCancelCalls, [
        (token: 'tok-124', reason: 'The item(s) are no longer needed'),
      ]);
      expect(account.cancelCalls, isEmpty);
      expect(find.text(en.orderCancelEmailSent), findsOneWidget);
    });
  });

  testWidgets('the sheet lays out right-to-left in Arabic', (tester) async {
    await _pump(
      tester,
      screen: const OrderDetailScreen(order: _open),
      locale: 'ar',
    );
    final ar = lookupAppLocalizations(const Locale('ar'));
    await tester.tap(find.text(ar.orderCancelAction));
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.text(ar.orderCancelReasonTitle))),
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });
}
