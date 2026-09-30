import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/routes.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/returns/domain/returns.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/fonts.dart';
import '../../support/returns_fakes.dart';
import 'returns_harness.dart';

/// Renders Figma 23 (65:2759 / AR 72:2956), 23b (65:2876 / 72:3073) and 23c
/// (65:2981 / 72:3178) in English and Arabic to `build/test_screens/` for
/// comparison with the frames (nothing is asserted on the images). Each
/// render also fails on any layout exception, so it doubles as an RTL and
/// overflow check.

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

/// The frame's order: one T-shirt from loly store.
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
    ),
    ReturnableItem(
      orderItemId: 602,
      name: ar ? 'حقيبة سفر' : 'Joust Duffle Bag',
      qtyOrdered: 1,
      qtyReturnable: 0,
      openReturnNumbers: const ['R-000027'],
      seller: _loly(ar),
    ),
    ReturnableItem(
      orderItemId: 603,
      name: ar ? 'كنبة سرير ركنه' : 'Corner Sofa Bed',
      options: [ReturnOption(label: 'Color', value: ar ? 'أزرق مخضر' : 'Teal')],
      qtyOrdered: 1,
      qtyReturnable: 1,
      seller: HmSellerSummary(
        name: 'MIA CO',
        code: 'miaco',
        vendorEntityId: 31,
      ),
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
);

FakeReturnsRepository _repo(bool ar, {bool closed = false}) =>
    FakeReturnsRepository(
      config: _config(ar),
      orders: [_order(ar), _twoSellers(ar)],
      units: const {
        '000000150': {501: Money(amount: 43, currency: 'AED')},
        '000000248': {
          601: Money(amount: 50, currency: 'AED'),
          602: Money(amount: 29, currency: 'AED'),
          603: Money(amount: 425, currency: 'AED'),
        },
      },
      summaries: [
        sampleReturnSummary(
          statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
          seller: _loly(ar),
          unread: true,
        ),
        sampleReturnSummary(
          id: 27,
          number: 'R-000027',
          state: ReturnState.closed,
          statusLabel: ar ? 'تم الاسترداد' : 'Refunded',
          seller: _test1(ar),
          createdAt: '2026-09-09T09:00:00Z',
        ),
        sampleReturnSummary(
          id: 19,
          number: 'R-000019',
          state: ReturnState.canceled,
          statusLabel: ar ? 'ملغي' : 'Canceled',
          type: ReturnType.replace,
          seller: _loly(ar),
          createdAt: '2026-09-02T09:00:00Z',
        ),
      ],
      details: {
        31: closed
            ? sampleReturnDetail(
                arabic: ar,
                state: ReturnState.closed,
                statusLabel: ar ? 'تم الحل' : 'Resolved',
              )
            : sampleReturnDetail(
                arabic: ar,
                statusLabel: ar ? 'بانتظار المتجر' : 'Awaiting store',
              ),
      },
    );

Future<void> _render(
  WidgetTester tester, {
  required String name,
  required String locale,
  required String location,
  Object? extra,
  double height = 844,
  bool closed = false,
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
      returns: _repo(locale == 'ar', closed: closed),
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
        height: 1340,
        then: (tester, l10n) async {
          await tester.tap(find.text(l10n.returnsChooseReason));
          await tester.pumpAndSettle();
          await tester.tap(find.text(_config(ar).reasons.first.label));
          await tester.pumpAndSettle();
          await tester.tap(find.text(l10n.returnsAnswerYes));
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
        height: 1000,
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
        height: 1000,
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
      1000.0,
    ),
    ('23b_my_returns', AppRoutes.returns, null, 844.0),
    ('23c_return_detail', AppRoutes.returnDetail(31), null, 1000.0),
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
