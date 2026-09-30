import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/help_faq.dart';
import 'package:hubmarket_app/features/cms/domain/cms_document.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/returns_fakes.dart';
import 'returns_harness.dart';

final en = lookupAppLocalizations(const Locale('en'));
final ar = lookupAppLocalizations(const Locale('ar'));

/// Every HubApp state in which returns must stay hidden (Build 1).
const _hidden = <(String, HubAppState)>[
  ('HubApp absent', HubAppState.unavailable()),
  ('HubApp not known yet', HubAppState.unknown()),
  ('returns flag off', kReturnsFlagOff),
  ('returns flag unset', kReturnsFlagUnset),
];

void main() {
  group('Account (20): My returns', () {
    testWidgets('listed under My Orders when returns are on', (tester) async {
      await pumpReturns(tester, location: AppRoutes.account);
      expect(find.text(en.returnsMyReturns), findsOneWidget);
      final orders = tester.getTopLeft(find.text(en.accountOrders)).dy;
      final returns = tester.getTopLeft(find.text(en.returnsMyReturns)).dy;
      expect(returns, greaterThan(orders));

      await tester.tap(find.text(en.returnsMyReturns));
      await tester.pumpAndSettle();
      expect(find.text(en.returnsEmptyTitle), findsOneWidget);
    });

    for (final (name, state) in _hidden) {
      testWidgets('hidden: $name', (tester) async {
        await pumpReturns(tester, location: AppRoutes.account, hubApp: state);
        expect(find.text(en.accountOrders), findsOneWidget);
        expect(find.text(en.returnsMyReturns), findsNothing);
      });
    }
  });

  group('Order detail (22): Return items', () {
    testWidgets('offered on a returnable order and opens the form on it', (
      tester,
    ) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(
        tester,
        location: AppRoutes.orderDetail,
        extra: kReturnableCustomerOrder,
        returns: repo,
      );
      expect(find.text(en.returnsReturnItems), findsOneWidget);
      // One request for this order, not a walk through the order pages.
      expect(repo.returnableOrderLookups, ['000000150']);
      expect(repo.returnableOrderPages, isEmpty);

      await tester.tap(find.text(en.returnsReturnItems));
      await tester.pumpAndSettle();
      expect(find.text(en.returnsRequestTitle), findsOneWidget);
      // The order is already chosen, its lines listed.
      expect(find.textContaining('#000000150'), findsOneWidget);
      expect(find.text('Short Square-Neck T-Shirt'), findsOneWidget);
      // The form reuses that answer.
      expect(repo.returnableOrderLookups, ['000000150']);
    });

    testWidgets('not offered when the order has nothing returnable', (
      tester,
    ) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(
        tester,
        location: AppRoutes.orderDetail,
        extra: const CustomerOrder(
          number: '000000151',
          status: 'Pending',
          date: '2026-09-28 10:42:00',
          id: 'MTUx',
        ),
        returns: repo,
      );
      expect(find.text(en.orderReorder), findsOneWidget);
      expect(find.text(en.returnsReturnItems), findsNothing);
      expect(repo.returnableOrderLookups, ['000000151']);
    });

    testWidgets('not offered on a guest order', (tester) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(
        tester,
        location: AppRoutes.orderDetail,
        extra: const CustomerOrder(
          number: '000000150',
          status: 'Complete',
          date: '2026-09-22 12:30:00',
          token: 'tok',
          placedAsGuest: true,
        ),
        returns: repo,
      );
      expect(find.text(en.returnsReturnItems), findsNothing);
      expect(repo.returnableOrderLookups, isEmpty);
      expect(repo.returnableOrderPages, isEmpty);
    });

    for (final (name, state) in _hidden) {
      testWidgets('hidden: $name', (tester) async {
        final repo = FakeReturnsRepository();
        await pumpReturns(
          tester,
          location: AppRoutes.orderDetail,
          extra: kReturnableCustomerOrder,
          hubApp: state,
          returns: repo,
        );
        expect(find.text(en.orderReorder), findsOneWidget);
        expect(find.text(en.returnsReturnItems), findsNothing);
        // Nothing is asked of a server that may not have returns.
        expect(repo.returnableOrderLookups, isEmpty);
        expect(repo.returnableOrderPages, isEmpty);
      });
    }
  });

  group('Help FAQ', () {
    test('the bundled answer follows returns', () {
      String answer(AppLocalizations l10n, {required bool inApp}) =>
          CmsDocument.plainText(
            bundledHelpFaq(
              l10n,
              returnsInApp: inApp,
            ).firstWhere((t) => t.icon == 'returns').items.single.answer,
          ).trim();
      for (final l10n in [en, ar]) {
        expect(answer(l10n, inApp: false), l10n.helpA8);
        expect(answer(l10n, inApp: true), l10n.helpA8Returns);
      }
    });

    testWidgets('the Returns topic tells how to return in the app', (
      tester,
    ) async {
      await pumpReturns(tester, location: AppRoutes.help);
      await tester.tap(find.text(en.helpTopicReturns));
      await tester.pumpAndSettle();
      expect(find.text(en.helpA8Returns), findsOneWidget);
      expect(find.text(en.helpA8), findsNothing);
    });

    testWidgets('without HubApp it keeps the Build 1 answer', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.help,
        hubApp: const HubAppState.unavailable(),
      );
      await tester.tap(find.text(en.helpTopicReturns));
      await tester.pumpAndSettle();
      expect(find.text(en.helpA8), findsOneWidget);
      expect(find.text(en.helpA8Returns), findsNothing);
    });
  });
}
