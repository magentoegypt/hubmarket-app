import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/data/return_photo_picker.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/my_returns_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/request_return_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/screens/return_detail_screen.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_photos.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/audit_pump.dart';
import '../../support/fonts.dart';
import '../../support/returns_fakes.dart';

/// Renders Figma 23 Request a return (65:2759 / 72:2956), 23b My returns
/// (65:2876 / 72:3073) and 23c Return detail (65:2981 / 72:3178) in English and
/// Arabic to build/test_screens/audit_23*_{en,ar}.png, with the frames' data.
HmSellerSummary _loly(bool ar) => HmSellerSummary(
  name: ar ? 'متجر لولي' : 'loly store',
  code: 'loly',
  vendorEntityId: 12,
);

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

/// The frame's order: one T-shirt from loly store, AED 43.
ReturnableOrder _order(bool ar) => ReturnableOrder(
  number: 'HM-100150',
  createdAt: '2026-09-22T08:30:00Z',
  statusLabel: ar ? 'تم التوصيل' : 'Delivered',
  items: [
    ReturnableItem(
      orderItemId: 501,
      sku: 'TS-S-GRN',
      name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
      options: [
        ReturnOption(label: ar ? 'المقاس' : 'Size', value: 'S'),
        ReturnOption(
          label: ar ? 'اللون' : 'Color',
          value: ar ? 'أخضر' : 'Green',
        ),
      ],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: _loly(ar),
      unitPrice: _aed(43),
      rowTotal: _aed(43),
      maxRefund: _aed(43),
    ),
  ],
);

ReturnConfig _config(bool ar) => ReturnConfig(
  reasonsEnabled: true,
  otherReasonAllowed: true,
  partialQuantityAllowed: true,
  reasons: [
    ReturnReason(
      id: 1,
      label: ar ? 'المقاس غير مناسب – صغير جدًا' : 'Doesn’t fit — too small',
    ),
    ReturnReason(id: 2, label: ar ? 'وصل تالفًا' : 'Arrived damaged'),
  ],
  attachmentExtensions: kPhotoReturnConfig.attachmentExtensions,
  attachmentMaxBytes: kPhotoReturnConfig.attachmentMaxBytes,
  attachmentMaxFiles: kPhotoReturnConfig.attachmentMaxFiles,
);

/// The three returns of Figma 23b: awaiting the store, refunded, rejected.
List<ReturnSummary> _summaries(bool ar) => [
  sampleReturnSummary(
    statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
    seller: _loly(ar),
    firstItem: ReturnSummaryItem(
      name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
    ),
  ),
  sampleReturnSummary(
    id: 27,
    number: 'R-000027',
    state: ReturnState.closed,
    statusLabel: ar ? 'تم الاسترداد' : 'Refunded',
    seller: const HmSellerSummary(name: 'Test 1', code: 'test1'),
    createdAt: '2026-09-09T09:00:00Z',
    refundAmount: _aed(29),
    firstItem: ReturnSummaryItem(name: ar ? 'حقيبة سفر' : 'Joust Duffle Bag'),
  ),
  sampleReturnSummary(
    id: 19,
    number: 'R-000019',
    state: ReturnState.closed,
    statusCode: 'rejected',
    statusLabel: ar ? 'مرفوض' : 'Rejected',
    type: ReturnType.replace,
    seller: _loly(ar),
    createdAt: '2026-09-02T09:00:00Z',
    firstItem: ReturnSummaryItem(name: ar ? 'قميص بولو' : 'Polo Shirt'),
  ),
];

/// Figma 23c: the customer's message and loly store's answer.
ReturnDetail _detail(bool ar) => sampleReturnDetail(
  arabic: ar,
  statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
  photo: false,
  canCancel: false,
  messages: [
    ReturnMessage(
      id: 1,
      author: ReturnActor.customer,
      authorName: ar ? 'سارة أحمد' : 'Sara Ahmed',
      bodyText: ar
          ? 'المقاس S صغير جدًا، أرجو ترتيب الاستلام. البطاقات ما زالت عليه.'
          : 'Size S is too small, please arrange a pickup. Tags are still on.',
      createdAt: '2026-09-24T14:02:00Z',
    ),
    ReturnMessage(
      id: 2,
      author: ReturnActor.seller,
      authorName: ar ? 'متجر لولي' : 'loly store',
      bodyText: ar
          ? 'أهلًا سارة، نعتذر عن المقاس! سيستلمه المندوب الثلاثاء 30 سبتمبر بين 10:00 و14:00.'
          : 'Hi Sara, sorry about the fit! A courier will collect it on Tue 30 Sep between 10:00 and 14:00.',
      createdAt: '2026-09-25T05:15:00Z',
    ),
  ],
);

FakeReturnsRepository _repo(bool ar) => FakeReturnsRepository(
  config: _config(ar),
  orders: [_order(ar)],
  summaries: _summaries(ar),
  details: {31: _detail(ar)},
);

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final ar = locale == 'ar';

    testWidgets('23 Request a return ($locale)', (tester) async {
      final key = GlobalKey();
      await withRealShadows(() async {
        await pumpAudit(
          tester,
          locale: locale,
          boundary: key,
          height: ar ? 1106 : 1086,
          screen: RequestReturnScreen(order: _order(ar)),
          returns: _repo(ar),
          overrides: [
            returnPhotoPickerProvider.overrideWithValue(
              FakeReturnPhotoPicker(photos: [kGreenPhoto]),
            ),
          ],
        );
        final l10n = lookupAppLocalizations(Locale(locale));
        await tester.tap(find.text(l10n.returnsChooseReason));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_config(ar).reasons.first.label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.returnsAnswerYes));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(ReturnAddPhotoTile));
        await tester.tap(find.byType(ReturnAddPhotoTile));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.returnsChoosePhotos));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
        await tester.pumpAndSettle();
        await captureScreen(tester, key, 'audit_23_request_return_$locale');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('23b My returns ($locale)', (tester) async {
      final key = GlobalKey();
      await withRealShadows(() async {
        await pumpAudit(
          tester,
          locale: locale,
          boundary: key,
          screen: const MyReturnsScreen(),
          returns: _repo(ar),
        );
        await captureScreen(tester, key, 'audit_23b_my_returns_$locale');
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('23c Return detail ($locale)', (tester) async {
      final key = GlobalKey();
      await withRealShadows(() async {
        await pumpAudit(
          tester,
          locale: locale,
          boundary: key,
          screen: const ReturnDetailScreen(returnId: 31),
          returns: _repo(ar),
        );
        await captureScreen(tester, key, 'audit_23c_return_detail_$locale');
        expect(tester.takeException(), isNull);
      });
    });
  }
}
