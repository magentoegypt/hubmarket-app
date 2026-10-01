import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/returns_fakes.dart';
import 'returns_harness.dart';
import 'package:hubmarket_app/app/theme/hub_icons.dart';

final en = lookupAppLocalizations(const Locale('en'));

Future<void> _pickOrder(WidgetTester tester, String number) async {
  await tester.tap(find.text(en.returnsChooseOrder));
  await tester.pumpAndSettle();
  await tester.tap(find.text('#$number').last);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester) async {
  await tester.tap(find.text(en.returnsSubmit));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  group('23b My returns', () {
    testWidgets('lists returns with status, outcome, seller and new replies', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returns,
        returns: FakeReturnsRepository(
          summaries: [
            sampleReturnSummary(unread: true),
            sampleReturnSummary(
              id: 27,
              number: 'R-000027',
              state: ReturnState.closed,
              statusLabel: 'Resolved',
              seller: kMiaCo,
            ),
            sampleReturnSummary(
              id: 19,
              number: 'R-000019',
              state: ReturnState.canceled,
              statusLabel: 'Canceled',
              type: ReturnType.replace,
            ),
          ],
        ),
      );

      expect(find.text(en.returnsMyReturns), findsOneWidget);
      expect(
        find.text(en.returnsTitle(returnNumberLabel('R-000031'))),
        findsOneWidget,
      );
      expect(find.text('AWAITING STORE'), findsOneWidget);
      expect(find.text('RESOLVED'), findsOneWidget);
      expect(find.text('CANCELED'), findsOneWidget);
      expect(
        find.text(
          '${en.returnsRequestedOn('24 Sep')} · ${en.returnsTypeRefund}',
        ),
        findsWidgets,
      );
      expect(
        find.text(
          '${en.returnsRequestedOn('24 Sep')} · ${en.returnsTypeReplace}',
        ),
        findsOneWidget,
      );
      expect(find.text(en.returnsSoldBy('loly store')), findsNWidgets(2));
      expect(find.text(en.returnsSoldBy('MIA CO')), findsOneWidget);
      expect(find.text(en.returnsNewReply), findsOneWidget);
      expect(find.text(en.returnsNewRequest), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a card opens its return, which then reads as read', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returns,
        returns: FakeReturnsRepository(
          summaries: [sampleReturnSummary(unread: true)],
          details: {31: sampleReturnDetail()},
        ),
      );
      await tester.tap(
        find.text(en.returnsTitle(returnNumberLabel('R-000031'))),
      );
      await tester.pumpAndSettle();
      expect(find.text(en.returnsYou), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text(en.returnsNewReply), findsNothing);
    });

    testWidgets('no returns yet offers a new request', (tester) async {
      await pumpReturns(tester, location: AppRoutes.returns);
      expect(find.text(en.returnsEmptyTitle), findsOneWidget);
      await tester.tap(find.text(en.returnsNewRequest));
      await tester.pumpAndSettle();
      expect(find.text(en.returnsRequestTitle), findsOneWidget);
    });

    testWidgets('a guest is asked to sign in', (tester) async {
      await pumpReturns(tester, location: AppRoutes.returns, signedIn: false);
      expect(find.text(en.returnsSignIn), findsOneWidget);
    });
  });

  group('23c Return detail', () {
    testWidgets('shows the lines, the thread and Hub Market for staff', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: FakeReturnsRepository(details: {31: sampleReturnDetail()}),
      );
      expect(
        find.text(en.returnsTitle(returnNumberLabel('R-000031'))),
        findsOneWidget,
      );
      expect(find.text('Short Square-Neck T-Shirt'), findsOneWidget);
      expect(find.text('AWAITING STORE'), findsOneWidget);
      expect(find.text('AED 43'), findsOneWidget);
      expect(
        find.text('${en.returnsEventSentTo('loly store')} · 24 Sep'),
        findsOneWidget,
      );
      expect(find.text(en.returnsYou), findsOneWidget);
      expect(find.text('loly store'), findsOneWidget);
      expect(find.text('Hub Market'), findsOneWidget);
      expect(find.textContaining('courier will collect'), findsOneWidget);
    });

    testWidgets('staff are Hub Market whatever name comes back', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: FakeReturnsRepository(
          details: {
            31: sampleReturnDetail(
              messages: const [
                ReturnMessage(
                  id: 5,
                  author: ReturnActor.hubMarket,
                  authorName: 'Ahmed from support',
                  bodyText: 'We are on it.',
                  createdAt: '2026-09-25T09:40:00Z',
                ),
              ],
            ),
          },
        ),
      );
      expect(find.text('Hub Market'), findsOneWidget);
      expect(find.text('Ahmed from support'), findsNothing);
    });

    testWidgets('an open return takes a reply', (tester) async {
      final repo = FakeReturnsRepository(details: {31: sampleReturnDetail()});
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
      );
      final field = find.widgetWithText(TextField, en.returnsWriteReply);
      expect(field, findsOneWidget);

      await tester.enterText(field, '  Any news on the pickup?  ');
      await tester.pump();
      await tester.tap(find.byTooltip(en.returnsSendReply));
      await tester.pumpAndSettle();

      expect(repo.replies, [
        (returnId: 31, message: 'Any news on the pickup?'),
      ]);
      expect(find.text('Any news on the pickup?'), findsOneWidget);
      final editable = tester.widget<TextField>(find.byType(TextField));
      expect(editable.controller!.text, isEmpty);
    });

    testWidgets('a closed return takes no replies', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: FakeReturnsRepository(
          details: {
            31: sampleReturnDetail(
              state: ReturnState.closed,
              statusLabel: 'Resolved',
            ),
          },
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip(en.returnsSendReply), findsNothing);
      expect(find.text(en.returnsClosedNote), findsOneWidget);
    });

    testWidgets('a refused reply says why and keeps the text', (tester) async {
      final repo = FakeReturnsRepository(
        details: {31: sampleReturnDetail()},
        replyFailure: const Failure(
          FailureKind.server,
          detail: 'This return is closed, so it can\'t take new messages.',
        ),
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
      );
      await tester.enterText(find.byType(TextField), 'Hello?');
      await tester.pump();
      await tester.tap(find.byTooltip(en.returnsSendReply));
      await tester.pumpAndSettle();
      expect(
        find.text('This return is closed, so it can\'t take new messages.'),
        findsOneWidget,
      );
      final editable = tester.widget<TextField>(find.byType(TextField));
      expect(editable.controller!.text, 'Hello?');
    });

    testWidgets('someone else’s return is not found', (tester) async {
      await pumpReturns(tester, location: AppRoutes.returnDetail(404));
      expect(find.text(en.returnsNotFound), findsOneWidget);
    });
  });

  group('23 Request a return', () {
    testWidgets('eligibility: held lines are off, one seller at a time', (
      tester,
    ) async {
      await pumpReturns(tester, location: AppRoutes.returnRequest);
      await _pickOrder(tester, '000000150');

      // The bag is already in R-000031.
      expect(
        find.text(en.returnsItemInReturn(returnNumberLabel('R-000031'))),
        findsOneWidget,
      );
      // Nothing ticked: both sellers' lines are available.
      expect(find.text(en.returnsOtherSellerNote('MIA CO')), findsNothing);
      expect(find.text(en.returnsSoldBy('loly store')), findsOneWidget);
      expect(find.text(en.returnsSoldBy('MIA CO')), findsOneWidget);

      await _tapVisible(tester, find.text('Short Square-Neck T-Shirt'));
      expect(find.text(en.returnsOtherSellerNote('MIA CO')), findsOneWidget);
      expect(
        find.text(en.returnsStoreNoteSeller('loly store')),
        findsOneWidget,
      );
      // The other seller's line can't join this return.
      await _tapVisible(tester, find.text('Corner Sofa Bed'));
      expect(find.text(en.returnsOtherSellerNote('MIA CO')), findsOneWidget);
      // The line prices come from the order.
      expect(find.text('S · Green · AED 43'), findsOneWidget);
      expect(find.text('AED 86'), findsOneWidget); // maximum refund
    });

    testWidgets('quantity stays within 1 and the returnable quantity', (
      tester,
    ) async {
      await pumpReturns(tester, location: AppRoutes.returnRequest);
      await _pickOrder(tester, '000000150');
      await _tapVisible(tester, find.text('Short Square-Neck T-Shirt'));

      final minus = find.widgetWithIcon(IconButton, HubIcons.minus);
      final plus = find.widgetWithIcon(IconButton, HubIcons.plus);
      expect(tester.widget<IconButton>(plus).onPressed, isNull); // at 2 of 2
      await _tapVisible(tester, minus);
      expect(find.text('AED 43'), findsOneWidget); // 1 × 43
      expect(tester.widget<IconButton>(minus).onPressed, isNull); // at 1
      await _tapVisible(tester, plus);
      expect(find.text('AED 86'), findsOneWidget);
    });

    testWidgets('a lone returnable line starts ticked', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
      );
      expect(find.text('Polo Shirt'), findsOneWidget);
      expect(find.text('×1'), findsOneWidget);
      expect(
        find.text(en.returnsStoreNoteSeller('Hub Market')),
        findsOneWidget,
      );
    });

    testWidgets('an incomplete request says what is missing, sends nothing', (
      tester,
    ) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        returns: repo,
      );
      await _pickOrder(tester, '000000150');
      await _submit(tester);

      expect(repo.createInputs, isEmpty);
      expect(find.text(en.returnsFixErrors), findsOneWidget);
      expect(find.text(en.returnsErrorItems), findsOneWidget);
      expect(find.text(en.returnsErrorReason), findsOneWidget);
      expect(find.text(en.returnsErrorPackage), findsOneWidget);
      expect(find.text(en.returnsErrorComment), findsOneWidget);
    });

    testWidgets('a custom refund above the lines’ amount is refused', (
      tester,
    ) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        returns: repo,
      );
      await _pickOrder(tester, '000000150');
      await _tapVisible(tester, find.text('Short Square-Neck T-Shirt'));
      await _tapVisible(tester, find.text(en.returnsCustomAmount));
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsCustomAmountHint),
        '90',
      );
      await _submit(tester);
      expect(find.text(en.returnsErrorAmountCap('AED 86')), findsOneWidget);
      expect(repo.createInputs, isEmpty);
    });

    testWidgets('a complete request files the return and opens it', (
      tester,
    ) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(tester, location: AppRoutes.returns, returns: repo);
      await tester.tap(find.text(en.returnsNewRequest));
      await tester.pumpAndSettle();

      await _pickOrder(tester, '000000150');
      await _tapVisible(tester, find.text('Short Square-Neck T-Shirt'));
      await _tapVisible(tester, find.widgetWithIcon(IconButton, HubIcons.minus));
      await _tapVisible(tester, find.text(en.returnsTypeReplace));
      await _tapVisible(tester, find.text(en.returnsChooseReason));
      await tester.tap(find.text('Arrived damaged'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.text(en.returnsAnswerNo));
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsCommentHint),
        'The strap is torn.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsTrackingHint),
        'ARX 3345 1182',
      );
      await _submit(tester);

      expect(repo.createInputs, [
        {
          'order_number': '000000150',
          'items': [
            {'order_item_id': 501, 'quantity': 1.0},
          ],
          'type': 'REPLACE',
          'reason_id': 2,
          'package_opened': false,
          'comment': 'The strap is torn.',
          'tracking_code': 'ARX 3345 1182',
        },
      ]);
      // On to the new return (23c).
      expect(
        find.text(en.returnsTitle(returnNumberLabel('R-000031'))),
        findsOneWidget,
      );
      expect(find.text(en.returnsYou), findsOneWidget);
    });

    testWidgets('a store refusal is shown and the form stays', (tester) async {
      final repo = FakeReturnsRepository(
        createFailure: const Failure(
          FailureKind.server,
          detail: 'You can return at most 1 of "Short Square-Neck T-Shirt".',
        ),
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kSingleLineOrder,
        returns: repo,
      );
      await _tapVisible(tester, find.text(en.returnsChooseReason));
      await tester.tap(find.text(en.returnsOtherReason));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsOtherReasonHint),
        'Changed my mind',
      );
      await _tapVisible(tester, find.text(en.returnsAnswerYes));
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsCommentHint),
        'Please collect it.',
      );
      await _submit(tester);

      expect(repo.createInputs.single['other_reason'], 'Changed my mind');
      expect(repo.createInputs.single.containsKey('reason_id'), isFalse);
      expect(repo.createInputs.single['refund_amount_type'], 'FULL');
      expect(
        find.text('You can return at most 1 of "Short Square-Neck T-Shirt".'),
        findsOneWidget,
      );
      expect(find.text(en.returnsRequestTitle), findsOneWidget);
    });

    testWidgets('opened on an order with nothing left to return', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequestFor('000000999'),
      );
      expect(
        find.text(en.returnsOrderNotReturnable('000000999')),
        findsOneWidget,
      );
      expect(find.text(en.returnsChooseOrder), findsOneWidget);
    });

    testWidgets('no returnable orders', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        returns: FakeReturnsRepository(orders: const []),
      );
      expect(find.text(en.returnsNoOrdersTitle), findsOneWidget);
    });
  });

  group('fallback', () {
    for (final (name, state) in [
      ('HubApp absent', const HubAppState.unavailable()),
      ('HubApp not known yet', const HubAppState.unknown()),
      ('returns flag off', kReturnsFlagOff),
      ('returns flag unset', kReturnsFlagUnset),
    ]) {
      testWidgets('$name: the screens say returns are not available', (
        tester,
      ) async {
        final repo = FakeReturnsRepository(
          summaries: [sampleReturnSummary()],
          details: {31: sampleReturnDetail()},
        );
        for (final location in [
          AppRoutes.returns,
          AppRoutes.returnRequest,
          AppRoutes.returnDetail(31),
        ]) {
          await pumpReturns(
            tester,
            location: location,
            hubApp: state,
            returns: repo,
          );
          expect(
            find.text(en.returnsUnavailableTitle),
            findsOneWidget,
            reason: location,
          );
        }
        expect(repo.createInputs, isEmpty);
        expect(repo.returnableOrderPages, isEmpty);
      });
    }

    testWidgets('a server without the returns module hides returns', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        returns: FakeReturnsRepository(missing: true),
      );
      expect(find.text(en.returnsUnavailableTitle), findsOneWidget);
    });
  });
}
