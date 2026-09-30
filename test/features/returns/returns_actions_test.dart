import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/app/theme/app_colors.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_photos.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_widgets.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/returns_fakes.dart';
import 'returns_harness.dart';

final en = lookupAppLocalizations(const Locale('en'));

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('23 line prices', () {
    testWidgets('come from the server’s lines, with no second lookup', (
      tester,
    ) async {
      final repo = FakeReturnsRepository();
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kTwoSellerOrder,
        returns: repo,
      );
      await _tapVisible(tester, find.text('Short Square-Neck T-Shirt'));
      expect(find.text('S · Green · AED 43.00'), findsOneWidget);
      expect(find.text('AED 86.00'), findsOneWidget); // max_refund
      expect(repo.unitRefundLookups, isEmpty);
    });

    testWidgets('from an older server, fall back on the core order', (
      tester,
    ) async {
      final repo = FakeReturnsRepository(orders: [kLegacyOrder]);
      await pumpReturns(
        tester,
        location: AppRoutes.returnRequest,
        extra: kLegacyOrder,
        returns: repo,
      );
      expect(repo.unitRefundLookups, ['000000140']);
      expect(find.text('AED 55.00'), findsOneWidget); // the mug, per unit
      expect(find.text('AED 165.00'), findsOneWidget); // 3 × 55

      // The cap a custom refund must stay under comes from there too.
      await _tapVisible(tester, find.text(en.returnsCustomAmount));
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsCustomAmountHint),
        '170',
      );
      await _tapVisible(tester, find.text(en.returnsSubmit));
      expect(find.text(en.returnsErrorAmountCap('AED 165.00')), findsOneWidget);
      expect(repo.createInputs, isEmpty);
    });
  });

  group('23b cards', () {
    testWidgets('show the first product, its thumbnail, the refund and how '
        'many more', (tester) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returns,
        returns: FakeReturnsRepository(
          summaries: [
            sampleReturnSummary(
              itemCount: 3,
              refundAmount: const Money(amount: 29, currency: 'AED'),
              firstItem: const ReturnSummaryItem(
                name: 'Short Square-Neck T-Shirt',
                thumbnail:
                    'https://hub-market.magento2.click/media/catalog/product/t/s/tshirt.jpg',
              ),
            ),
          ],
        ),
      );
      expect(find.text('Short Square-Neck T-Shirt'), findsOneWidget);
      expect(find.text(en.returnsMoreItems(2)), findsOneWidget);
      expect(
        find.text(
          '${en.returnsRequestedOn('24 Sep')} · '
          '${en.returnsTypeRefund} ⁦AED 29.00⁩',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<ReturnThumb>(find.byType(ReturnThumb)).url,
        'https://hub-market.magento2.click/media/catalog/product/t/s/tshirt.jpg',
      );
    });

    testWidgets('without a first line, the order and its line count', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returns,
        returns: FakeReturnsRepository(
          summaries: [sampleReturnSummary(firstItem: null, itemCount: 2)],
        ),
      );
      expect(
        find.text('${en.orderNumber('000000150')} · ${en.orderItemCount(2)}'),
        findsOneWidget,
      );
      expect(find.text(en.returnsMoreItems(1)), findsNothing);
      expect(tester.widget<ReturnThumb>(find.byType(ReturnThumb)).url, isNull);
    });

    testWidgets('colour a return by its status: handled, resolved, rejected', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returns,
        returns: FakeReturnsRepository(
          summaries: [
            sampleReturnSummary(),
            sampleReturnSummary(
              id: 28,
              number: 'R-000028',
              state: ReturnState.closed,
              statusLabel: 'Resolved',
            ),
            // Closed as well, but refused: it must not read as resolved.
            sampleReturnSummary(
              id: 27,
              number: 'R-000027',
              state: ReturnState.closed,
              statusCode: 'rejected',
              statusLabel: 'Rejected',
            ),
            sampleReturnSummary(
              id: 19,
              number: 'R-000019',
              state: ReturnState.canceled,
              statusLabel: 'Canceled',
            ),
          ],
        ),
      );
      expect(_colorOf(tester, 'AWAITING STORE'), AppColors.warning);
      expect(_colorOf(tester, 'RESOLVED'), AppColors.successStrong);
      expect(_colorOf(tester, 'REJECTED'), AppColors.danger);
      expect(_colorOf(tester, 'CANCELED'), AppColors.danger);
    });
  });

  group('23c what the customer may do', () {
    testWidgets('no reply box when the server says it takes no replies', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: FakeReturnsRepository(
          details: {
            // Still open, but the server says no.
            31: sampleReturnDetail(
              canReply: false,
              canCancel: false,
              canEscalate: false,
            ),
          },
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.text(en.returnsClosedNote), findsOneWidget);
      expect(find.text(en.returnsEscalatePrompt), findsNothing);
      expect(find.text(en.returnsCancelAction), findsNothing);
    });

    testWidgets('a reply box whenever the server says it takes replies', (
      tester,
    ) async {
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: FakeReturnsRepository(
          details: {
            31: sampleReturnDetail(
              state: ReturnState.closed,
              statusLabel: 'Resolved',
              canReply: true,
            ),
          },
        ),
      );
      expect(
        find.widgetWithText(TextField, en.returnsWriteReply),
        findsOneWidget,
      );
      expect(find.text(en.returnsClosedNote), findsNothing);
    });

    testWidgets('escalate: a message is required; photos go with it', (
      tester,
    ) async {
      final repo = FakeReturnsRepository(
        config: kPhotoReturnConfig,
        details: {31: sampleReturnDetail(photo: false)},
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
        photoPicker: FakeReturnPhotoPicker(photos: [kGreenPhoto]),
      );
      expect(find.text(en.returnsEscalatePrompt), findsOneWidget);
      await _tapVisible(tester, find.text(en.returnsEscalate));
      expect(find.text(en.returnsEscalateTitle), findsOneWidget);

      await tester.tap(find.text(en.returnsEscalateSubmit));
      await tester.pumpAndSettle();
      expect(find.text(en.returnsEscalateError), findsOneWidget);
      expect(repo.escalations, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, en.returnsEscalateHint),
        'The store stopped answering.',
      );
      await tester.pump();
      expect(find.text(en.returnsEscalateError), findsNothing);
      await _tapVisible(tester, find.byType(ReturnAddPhotoTile));
      await tester.tap(find.text(en.returnsChoosePhotos));
      await tester.pumpAndSettle();
      expect(find.byType(ReturnPhotoTile), findsOneWidget);

      await _tapVisible(tester, find.text(en.returnsEscalateSubmit));
      final sent = repo.escalations.single;
      expect(sent.returnId, 31);
      expect(sent.message, 'The store stopped answering.');
      expect(sent.photos.single.mimeType, 'image/png');

      // The sheet is gone; the escalation is in the thread, once.
      expect(find.text(en.returnsEscalateTitle), findsNothing);
      expect(find.text(en.returnsEscalated), findsOneWidget);
      expect(find.text(en.returnsEscalationTitle), findsOneWidget);
      expect(find.text('The store stopped answering.'), findsOneWidget);
      expect(find.byType(ReturnAttachmentStrip), findsOneWidget);
      expect(find.text(en.returnsEscalatePrompt), findsNothing);
      expect(find.text(en.returnsCancelAction), findsNothing);
      expect(find.text('ESCALATED'), findsOneWidget);
    });

    testWidgets('escalate: a refusal is shown in the sheet, the text kept', (
      tester,
    ) async {
      final repo = FakeReturnsRepository(
        details: {31: sampleReturnDetail()},
        escalateFailure: const Failure(
          FailureKind.server,
          detail: 'This return has already been escalated.',
        ),
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
      );
      await _tapVisible(tester, find.text(en.returnsEscalate));
      // The store takes no photos: none are offered.
      expect(find.byType(ReturnAddPhotoTile), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, en.returnsEscalateHint),
        'Nobody answers.',
      );
      await _tapVisible(tester, find.text(en.returnsEscalateSubmit));

      expect(repo.escalations.single.photos, isEmpty);
      expect(
        find.text('This return has already been escalated.'),
        findsOneWidget,
      );
      expect(find.text(en.returnsEscalateTitle), findsOneWidget);
      expect(find.text('Nobody answers.'), findsOneWidget);
    });

    testWidgets('cancel asks first; Keep it changes nothing', (tester) async {
      final repo = FakeReturnsRepository(details: {31: sampleReturnDetail()});
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
      );
      await _tapVisible(tester, find.text(en.returnsCancelAction));
      expect(find.text(en.returnsCancelTitle), findsOneWidget);
      expect(find.text(en.returnsCancelBody), findsOneWidget);

      await tester.tap(find.text(en.returnsCancelKeep));
      await tester.pumpAndSettle();
      expect(repo.cancellations, isEmpty);
      expect(find.text(en.returnsCancelTitle), findsNothing);
      expect(find.text('AWAITING STORE'), findsOneWidget);

      await _tapVisible(tester, find.text(en.returnsCancelAction));
      await tester.tap(find.text(en.returnsCancelConfirm));
      await tester.pumpAndSettle();
      expect(repo.cancellations, [31]);
      expect(find.text(en.returnsCancelled), findsOneWidget);
      expect(find.text('CANCELED'), findsWidgets);
      // Cancelled: no replies, no escalation, nothing more to cancel.
      expect(find.byType(TextField), findsNothing);
      expect(find.text(en.returnsClosedNote), findsOneWidget);
      expect(find.text(en.returnsEscalatePrompt), findsNothing);
      expect(find.text(en.returnsCancelAction), findsNothing);
    });

    testWidgets('a refused cancellation says why and keeps the return', (
      tester,
    ) async {
      final repo = FakeReturnsRepository(
        details: {31: sampleReturnDetail()},
        cancelFailure: const Failure(
          FailureKind.server,
          detail: 'This return can no longer be cancelled.',
        ),
      );
      await pumpReturns(
        tester,
        location: AppRoutes.returnDetail(31),
        returns: repo,
      );
      await _tapVisible(tester, find.text(en.returnsCancelAction));
      await tester.tap(find.text(en.returnsCancelConfirm));
      await tester.pumpAndSettle();
      expect(repo.cancellations, [31]);
      expect(
        find.text('This return can no longer be cancelled.'),
        findsOneWidget,
      );
      expect(find.text(en.returnsCancelAction), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
