import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/account/presentation/account_screen.dart';
import 'package:hubmarket_app/features/store_credit/domain/store_credit.dart';
import 'package:hubmarket_app/features/store_credit/presentation/my_credit_screen.dart';

import '../../support/fonts.dart';
import '../../support/store_credit_fakes.dart';
import 'store_credit_harness.dart';

/// A page of [count] spends, ids from [firstId] down.
List<StoreCreditTransaction> _spends(int count, {required int firstId}) => [
  for (var i = 0; i < count; i++)
    StoreCreditTransaction(
      id: firstId - i,
      type: 'spend_credit',
      typeLabel: 'Used at checkout',
      amount: aedCredit(-5),
      balanceAfter: aedCredit(100.0 + i),
      description: 'Spent credit on order #0000${firstId - i}',
      createdAt: '2026-09-20T11:02:00Z',
    ),
];

Future<void> _pump(
  WidgetTester tester,
  FakeStoreCreditRepository credit, {
  Widget screen = const MyCreditScreen(),
  String locale = 'en',
  double height = 844,
  bool signedIn = true,
  bool deployed = true,
  bool creditOn = true,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = Size(390, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    storeCreditHarness(
      screen: screen,
      credit: credit,
      locale: locale,
      signedIn: signedIn,
      hubApp: creditHubApp(deployed: deployed, creditOn: creditOn),
      boundary: boundary,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  group('20d My credit', () {
    testWidgets('shows the balance, the checkout rule and the transactions', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository();
      await _pump(tester, credit);

      expect(find.text('My credit'), findsOneWidget);
      expect(find.text('Credit balance'), findsOneWidget);
      expect(find.text('AED 120.00'), findsOneWidget);
      expect(
        find.text('Use it on any order at checkout — it never expires.'),
        findsOneWidget,
      );
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Refund to credit'), findsOneWidget);
      expect(find.text('+ AED 43.00'), findsOneWidget);
      expect(find.text('\u2212 AED 23.00'), findsOneWidget);
      expect(find.text('Used at checkout'), findsOneWidget);
      expect(find.text('Spent credit on order #000000231'), findsOneWidget);
      expect(find.text('26 Sep 2026'), findsOneWidget);
      expect(credit.calls, ['fetchAccount:1']);
      // Nothing the backend can't do: no top-up.
      expect(find.text('Buy credit'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('says when the customer group may not spend credit', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeStoreCreditRepository(pages: [sampleCreditAccount(canUse: false)]),
      );
      expect(
        find.text('Store credit can’t be used at checkout on your account.'),
        findsOneWidget,
      );
      expect(
        find.text('Use it on any order at checkout — it never expires.'),
        findsNothing,
      );
    });

    testWidgets('an account with no transactions says so', (tester) async {
      await _pump(
        tester,
        FakeStoreCreditRepository(
          pages: [sampleCreditAccount(transactions: const [])],
        ),
      );
      expect(find.text('No transactions yet'), findsOneWidget);
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      final credit = FakeStoreCreditRepository(
        pages: [
          sampleCreditAccount(
            transactions: _spends(20, firstId: 100),
            currentPage: 1,
            totalPages: 2,
          ),
          sampleCreditAccount(
            transactions: _spends(3, firstId: 80),
            currentPage: 2,
            totalPages: 2,
          ),
        ],
      );
      await _pump(tester, credit);
      expect(credit.calls, ['fetchAccount:1']);

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();

      expect(credit.calls, ['fetchAccount:1', 'fetchAccount:2']);
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text('Spent credit on order #000078'), findsOneWidget);
      // The last page is in: no further request.
      expect(credit.calls, ['fetchAccount:1', 'fetchAccount:2']);
    });

    testWidgets('a failed load offers a retry', (tester) async {
      final credit = FakeStoreCreditRepository()
        ..nextError = const Failure(FailureKind.server, detail: 'boom');
      await _pump(tester, credit);
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('AED 120.00'), findsOneWidget);
      expect(credit.calls, ['fetchAccount:1', 'fetchAccount:1']);
    });
  });

  group('20 Account → My credit', () {
    testWidgets('shows the row with the balance and opens 20d', (tester) async {
      await _pump(
        tester,
        FakeStoreCreditRepository(),
        screen: const AccountScreen(),
        height: 1400,
      );

      expect(find.text('My credit'), findsOneWidget);
      expect(find.text('AED 120.00'), findsOneWidget);
      await tester.ensureVisible(find.text('My credit'));
      await tester.tap(find.text('My credit'));
      await tester.pumpAndSettle();
      expect(find.text('route /my-credit'), findsOneWidget);
    });

    testWidgets('hidden while the backend has no store credit', (tester) async {
      final credit = FakeStoreCreditRepository();
      await _pump(
        tester,
        credit,
        screen: const AccountScreen(),
        height: 1400,
        deployed: false,
      );
      expect(find.text('Log Out'), findsOneWidget);
      expect(find.text('My credit'), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('hidden while the store_credit switch is off', (tester) async {
      final credit = FakeStoreCreditRepository();
      await _pump(
        tester,
        credit,
        screen: const AccountScreen(),
        height: 1400,
        creditOn: false,
      );
      expect(find.text('My credit'), findsNothing);
      expect(credit.calls, isEmpty);
    });

    testWidgets('hides again once the server turns out to lack the module', (
      tester,
    ) async {
      final credit = FakeStoreCreditRepository()..missing = true;
      await _pump(tester, credit, screen: const AccountScreen(), height: 1400);
      expect(credit.calls, ['fetchBalance']);
      expect(find.text('My credit'), findsNothing);
    });
  });

  group('20d renders', () {
    for (final locale in ['en', 'ar']) {
      testWidgets('20d My credit ($locale)', (tester) async {
        final key = GlobalKey();
        await withRealShadows(() async {
          await _pump(
            tester,
            FakeStoreCreditRepository(
              pages: [sampleCreditAccount(arabic: locale == 'ar')],
            ),
            locale: locale,
            height: 761,
            boundary: key,
          );
          await captureScreen(tester, key, '20d_my_credit_$locale');
        });
        expect(
          Directionality.of(tester.element(find.byType(MyCreditScreen))),
          locale == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
