import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/features/returns/presentation/widgets/return_photos.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import '../../support/returns_fakes.dart';
import 'returns_harness.dart';

/// Renders Figma 23 (65:2759 / AR 72:2956), 23b (65:2876 / 72:3073) and 23c
/// (65:2981 / 72:3178) in English and Arabic to `build/test_screens/` for
/// comparison with the frames (nothing is asserted on the images). Each
/// render also fails on any layout exception, so it doubles as an RTL and
/// overflow check.
///
/// Tests can't load network images: product thumbnails and the thread's
/// photos show their placeholders, so the thread here carries none; the
/// photos a customer picks (in memory) show as they are.

HmSellerSummary _loly(bool ar) => HmSellerSummary(
  name: ar ? 'متجر لولي' : 'loly store',
  code: 'loly',
  vendorEntityId: 12,
);

HmSellerSummary _test1(bool ar) => HmSellerSummary(
  name: ar ? 'Test 1' : 'Test 1',
  code: 'test1',
  vendorEntityId: 14,
);

Money _aed(double amount) => Money(amount: amount, currency: 'AED');

/// The frame's order: one T-shirt from loly store, AED 43.
ReturnableOrder _order(bool ar) => ReturnableOrder(
  number: '000000150',
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

/// Two sellers in one order: the one-seller rule at work.
ReturnableOrder _twoSellers(bool ar) => ReturnableOrder(
  number: '000000248',
  createdAt: '2026-09-28T06:42:00Z',
  statusLabel: ar ? 'قيد التنفيذ' : 'Processing',
  items: [
    ReturnableItem(
      orderItemId: 601,
      name: ar ? 'فستان بطبعة الأزهار' : 'Floral Print Corset-Waist Tie Dress',
      options: [ReturnOption(label: 'Size', value: 'M')],
      qtyOrdered: 2,
      qtyReturnable: 2,
      seller: _loly(ar),
      unitPrice: _aed(50),
      rowTotal: _aed(100),
      maxRefund: _aed(100),
    ),
    ReturnableItem(
      orderItemId: 602,
      name: ar ? 'حقيبة سفر' : 'Joust Duffle Bag',
      qtyOrdered: 1,
      qtyReturnable: 0,
      openReturnNumbers: const ['R-000027'],
      seller: _loly(ar),
      unitPrice: _aed(29),
      rowTotal: _aed(29),
      maxRefund: _aed(0),
    ),
    ReturnableItem(
      orderItemId: 603,
      name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
      options: [ReturnOption(label: 'Color', value: ar ? 'أزرق مخضر' : 'Teal')],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: const HmSellerSummary(
        name: 'MIA CO',
        code: 'miaco',
        vendorEntityId: 31,
      ),
      unitPrice: _aed(425),
      rowTotal: _aed(425),
      maxRefund: _aed(425),
    ),
  ],
);

/// The store's settings, with the website's default upload rules: photos on.
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

ReturnDetail _detail(bool ar, {bool closed = false, bool escalated = false}) {
  if (closed) {
    return sampleReturnDetail(
      arabic: ar,
      state: ReturnState.closed,
      statusLabel: ar ? 'تم الحل' : 'Resolved',
      photo: false,
    );
  }
  final open = sampleReturnDetail(
    arabic: ar,
    statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
    photo: false,
  );
  if (!escalated) return open;
  return changedReturn(
    open,
    statusCode: 'awaiting',
    statusLabel: ar ? 'تم التصعيد' : 'Escalated',
    history: [
      ...open.history,
      ReturnHistoryEntry(
        statusCode: 'awaiting',
        statusLabel: ar ? 'تم التصعيد' : 'Escalated',
        changedBy: ReturnActor.customer,
        createdAt: '2026-09-26T08:00:00Z',
      ),
    ],
    canCancel: false,
    canEscalate: false,
    escalation: ReturnEscalation(
      bodyText: ar
          ? 'لم يرد المتجر منذ يومين ولم يأتِ المندوب.'
          : 'The store hasn’t answered for two days and no courier came.',
      createdAt: '2026-09-26T08:00:00Z',
    ),
  );
}

FakeReturnsRepository _repo(
  bool ar, {
  bool closed = false,
  bool escalated = false,
}) => FakeReturnsRepository(
  config: _config(ar),
  orders: [_order(ar), _twoSellers(ar)],
  summaries: [
    sampleReturnSummary(
      statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
      seller: _loly(ar),
      unread: true,
      firstItem: ReturnSummaryItem(
        name: ar ? 'تيشيرت قصير ياقة مربع' : 'Short Square-Neck T-Shirt',
      ),
    ),
    sampleReturnSummary(
      id: 27,
      number: 'R-000027',
      state: ReturnState.closed,
      statusLabel: ar ? 'تم الاسترداد' : 'Refunded',
      seller: _test1(ar),
      createdAt: '2026-09-09T09:00:00Z',
      refundAmount: _aed(29),
      firstItem: ReturnSummaryItem(name: ar ? 'حقيبة سفر' : 'Joust Duffle Bag'),
    ),
    sampleReturnSummary(
      id: 19,
      number: 'R-000019',
      state: ReturnState.canceled,
      statusCode: 'canceled',
      statusLabel: ar ? 'مرفوض' : 'Rejected',
      type: ReturnType.replace,
      seller: _loly(ar),
      createdAt: '2026-09-02T09:00:00Z',
      firstItem: ReturnSummaryItem(name: ar ? 'قميص بولو' : 'Polo Shirt'),
      itemCount: 2,
    ),
  ],
  details: {31: _detail(ar, closed: closed, escalated: escalated)},
);

Future<void> _render(
  WidgetTester tester, {
  required String name,
  required String locale,
  required String location,
  Object? extra,
  double height = 844,
  bool closed = false,
  bool escalated = false,
  bool dark = false,
  Future<void> Function(WidgetTester tester, AppLocalizations l10n)? then,
}) async {
  final boundary = GlobalKey();
  await withRealShadows(() async {
    await pumpReturns(
      tester,
      location: location,
      extra: extra,
      locale: locale,
      returns: _repo(locale == 'ar', closed: closed, escalated: escalated),
      photoPicker: FakeReturnPhotoPicker(photos: [kGreenPhoto, kGreyPhoto]),
      size: Size(390, height),
      boundary: boundary,
      dark: dark,
    );
    if (then != null) {
      await then(tester, lookupAppLocalizations(Locale(locale)));
    }
    expect(tester.takeException(), isNull);
    await captureScreen(
      tester,
      boundary,
      '${name}_$locale${dark ? '_dark' : ''}',
    );
  });
}

/// Adds the picker's photos through the Add tile or the camera button,
/// scrolling [scrollable] to it first when it is given.
Future<void> _addPhotos(
  WidgetTester tester,
  AppLocalizations l10n,
  Finder button, {
  Finder? scrollable,
}) async {
  if (scrollable != null) {
    await tester.scrollUntilVisible(button, 200, scrollable: scrollable);
  }
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.returnsChoosePhotos));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in const ['en', 'ar']) {
    final ar = locale == 'ar';

    testWidgets('23 Request a return ($locale)', (tester) async {
      await _render(
        tester,
        name: '23_request_return',
        locale: locale,
        location: AppRoutes.returnRequestFor('000000150'),
        extra: _order(ar),
        height: 1480,
        then: (tester, l10n) async {
          await tester.tap(find.text(l10n.returnsChooseReason));
          await tester.pumpAndSettle();
          await tester.tap(find.text(_config(ar).reasons.first.label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.returnsAnswerYes));
          await tester.pumpAndSettle();
          await _addPhotos(
            tester,
            l10n,
            find.byType(ReturnAddPhotoTile),
            scrollable: find.byType(Scrollable).first,
          );
          // Back to the top, as the frame shows it.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 3000),
          );
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('23 Request a return, two sellers ($locale)', (tester) async {
      await _render(
        tester,
        name: '23_request_return_two_sellers',
        locale: locale,
        location: AppRoutes.returnRequest,
        extra: _twoSellers(ar),
        height: 1100,
        then: (tester, l10n) async {
          await tester.tap(find.text(_twoSellers(ar).items.first.name));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('23b My returns ($locale)', (tester) async {
      await _render(
        tester,
        name: '23b_my_returns',
        locale: locale,
        location: AppRoutes.returns,
      );
    });

    testWidgets('23c Return detail ($locale)', (tester) async {
      await _render(
        tester,
        name: '23c_return_detail',
        locale: locale,
        location: AppRoutes.returnDetail(31),
        height: 1100,
      );
    });

    testWidgets('23c Return detail, a photo to send ($locale)', (tester) async {
      await _render(
        tester,
        name: '23c_return_detail_photo_reply',
        locale: locale,
        location: AppRoutes.returnDetail(31),
        height: 1100,
        then: (tester, l10n) async {
          await _addPhotos(tester, l10n, find.byTooltip(l10n.returnsAddPhotos));
          await tester.enterText(
            find.byType(TextField),
            ar ? 'هذه صورة الضرر.' : 'Here is the damage.',
          );
          await tester.pump();
        },
      );
    });

    testWidgets('23c Escalate to Hub Market ($locale)', (tester) async {
      await _render(
        tester,
        name: '23c_escalate_sheet',
        locale: locale,
        location: AppRoutes.returnDetail(31),
        then: (tester, l10n) async {
          await tester.ensureVisible(find.text(l10n.returnsEscalate));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.returnsEscalate));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.widgetWithText(TextField, l10n.returnsEscalateHint),
            ar
                ? 'لم يرد المتجر منذ يومين.'
                : 'The store hasn’t answered for two days.',
          );
          await _addPhotos(tester, l10n, find.byType(ReturnAddPhotoTile));
        },
      );
    });

    testWidgets('23c Return detail, escalated ($locale)', (tester) async {
      await _render(
        tester,
        name: '23c_return_detail_escalated',
        locale: locale,
        location: AppRoutes.returnDetail(31),
        height: 1100,
        escalated: true,
      );
    });

    testWidgets('20 Account with My returns ($locale)', (tester) async {
      await _render(
        tester,
        name: '20_account_my_returns',
        locale: locale,
        location: AppRoutes.account,
        height: 1000,
      );
    });

    testWidgets('22 Order detail with Return items ($locale)', (tester) async {
      await _render(
        tester,
        name: '22_order_detail_return_items',
        locale: locale,
        location: AppRoutes.orderDetail,
        extra: kReturnableCustomerOrder,
      );
    });

    testWidgets('23c Return detail, closed ($locale)', (tester) async {
      await _render(
        tester,
        name: '23c_return_detail_closed',
        locale: locale,
        location: AppRoutes.returnDetail(31),
        height: 1000,
        closed: true,
      );
    });
  }

  // The dark theme: the form's fields, the cards and the bubbles stay light
  // surfaces with their own ink; only what sits on the page follows it.
  for (final (name, location, extra, height) in [
    (
      '23_request_return',
      AppRoutes.returnRequest,
      _twoSellers(false) as Object?,
      1100.0,
    ),
    ('23b_my_returns', AppRoutes.returns, null, 844.0),
    ('23c_return_detail', AppRoutes.returnDetail(31), null, 1100.0),
  ]) {
    testWidgets('$name (en, dark)', (tester) async {
      await _render(
        tester,
        name: name,
        locale: 'en',
        location: location,
        extra: extra,
        height: height,
        dark: true,
      );
    });
  }
}
