import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/account/presentation/screens/guest_track_order_screen.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/l10n/l10n.dart';

import '../../support/audit_pump.dart';
import '../../support/fonts.dart';
import '../../support/marketplace_fakes.dart';

/// Renders Figma 26 "Track order" for a guest (85:3365 / 99:3944) in English
/// and Arabic to build/test_screens/audit_26_track_order_{en,ar}.png, filled in
/// and with the order it finds under the form, and checks what it does.
Money _aed(double amount) => Money(amount: amount, currency: 'AED');

/// Answers the lookup with [order], or refuses it with [error].
class _GuestRepo implements AccountRepository {
  _GuestRepo({this.order, this.error});

  final CustomerOrder? order;
  final Object? error;

  /// What the form sent.
  final List<({String number, String email, String lastname})> lookups = [];

  @override
  Future<CustomerOrder> fetchGuestOrder({
    required String number,
    required String email,
    required String lastname,
  }) async {
    lookups.add((number: number, email: email, lastname: lastname));
    if (error != null) throw error!;
    return order!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Order HM-100248 as a guest finds it: loly store's dress shipped, MIA CO's
/// sofa and chair still being prepared.
CustomerOrder _order(String locale, {bool shipped = true}) {
  final ar = locale == 'ar';
  final loly = seller('loly', ar ? 'متجر لولي' : 'loly store');
  final mia = seller('mia', ar ? 'ميا كو' : 'MIA CO');
  return CustomerOrder(
    number: 'HM-100248',
    status: ar ? 'في الطريق إليك' : 'Out for delivery',
    date: '2026-09-28 10:42:00',
    token: 'tok-248',
    placedAsGuest: true,
    invoiceCount: 1,
    shipmentCount: shipped ? 1 : 0,
    total: _aed(553),
    lines: [
      OrderLine(name: 'Dress', quantity: 1, seller: loly, uid: 'a'),
      OrderLine(name: 'Sofa', quantity: 1, seller: mia, uid: 'b'),
      OrderLine(name: 'Chair', quantity: 2, seller: mia, uid: 'c'),
    ],
    packages: [
      OrderPackage(
        seller: loly,
        statusCode: 'processing',
        statusLabel: 'Out for delivery',
        state: 'processing',
        itemUids: const ['a'],
        shipments: shipped
            ? const [OrderPackageShipment(id: 's', number: '31')]
            : const [],
      ),
      OrderPackage(
        seller: mia,
        statusCode: 'new',
        statusLabel: 'Processing',
        state: 'new',
        itemUids: const ['b', 'c'],
      ),
    ],
  );
}

/// Fills the form as the frame does and presses Find order.
Future<void> _fillAndFind(WidgetTester tester, String locale) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), 'HM-100248');
  await tester.enterText(fields.at(1), locale == 'ar' ? 'أحمد' : 'Ahmed');
  await tester.enterText(fields.at(2), 'sara.ahmed@gmail.com');
  final l10n = lookupAppLocalizations(Locale(locale));
  await tester.tap(find.text(l10n.guestTrackSubmit));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  for (final locale in ['en', 'ar']) {
    testWidgets('26 Track order ($locale)', (tester) async {
      final key = GlobalKey();
      await pumpAudit(
        tester,
        locale: locale,
        boundary: key,
        signedIn: false,
        screen: const GuestTrackOrderScreen(),
        account: _GuestRepo(order: _order(locale)),
      );
      await _fillAndFind(tester, locale);
      await captureScreen(tester, key, 'audit_26_track_order_$locale');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('26 Track order: the form before a lookup', (tester) async {
    final key = GlobalKey();
    await pumpAudit(
      tester,
      boundary: key,
      signedIn: false,
      screen: const GuestTrackOrderScreen(),
      account: _GuestRepo(order: _order('en')),
    );
    await captureScreen(tester, key, 'audit_26_track_order_empty_en');
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text('Track order'), findsOneWidget);
    expect(find.text(l10n.guestTrackHeading), findsOneWidget);
    for (final label in ['Order number', 'Billing last name', 'Email address']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Find order'), findsOneWidget);
    // A guest can sign in from the footer.
    expect(find.text('Have an account?'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    // No result until a lookup, and no guest return to look up.
    expect(find.text('View order details'), findsNothing);
    expect(find.text('Return an item'), findsNothing);
  });

  testWidgets('26 Track order: the order found shows under the form', (
    tester,
  ) async {
    final repo = _GuestRepo(order: _order('en'));
    await pumpAudit(
      tester,
      signedIn: false,
      screen: const GuestTrackOrderScreen(),
      account: repo,
    );
    await _fillAndFind(tester, 'en');

    // Sent as typed (the device then re-reads the order it remembers).
    expect(
      repo.lookups.first,
      (number: 'HM-100248', email: 'sara.ahmed@gmail.com', lastname: 'Ahmed'),
    );
    expect(find.text('Order #HM-100248'), findsOneWidget);
    expect(find.text('OUT FOR DELIVERY'), findsOneWidget);
    expect(
      find.text('Placed 28 Sep 2026 · 3 items · 2 packages'),
      findsOneWidget,
    );
    // Confirmed, packed and shipped are behind it; delivery is ahead.
    for (final step in ['Confirmed', 'Packed', 'Shipped', 'Delivered']) {
      expect(find.text(step), findsOneWidget);
    }
    expect(find.text('View order details'), findsOneWidget);

    // View order details opens the order page rather than replacing the form.
    await tester.tap(find.text('View order details'));
    await tester.pumpAndSettle();
    expect(find.text('STUB'), findsOneWidget);
  });

  testWidgets('26 Track order: editing the form drops the stale result', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      signedIn: false,
      screen: const GuestTrackOrderScreen(),
      account: _GuestRepo(order: _order('en')),
    );
    await _fillAndFind(tester, 'en');
    expect(find.text('View order details'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'Someone');
    await tester.pumpAndSettle();
    expect(find.text('View order details'), findsNothing);
  });

  testWidgets('26 Track order: an unknown order says what the store said', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      signedIn: false,
      screen: const GuestTrackOrderScreen(),
      account: _GuestRepo(
        error: const Failure(
          FailureKind.server,
          detail: 'We couldn\'t locate an order with the information provided.',
        ),
      ),
    );
    await _fillAndFind(tester, 'en');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('View order details'), findsNothing);
  });

  testWidgets('26 Track order: a form left empty asks for each field', (
    tester,
  ) async {
    final repo = _GuestRepo(order: _order('en'));
    await pumpAudit(
      tester,
      signedIn: false,
      screen: const GuestTrackOrderScreen(),
      account: repo,
    );
    await tester.tap(find.text('Find order'));
    await tester.pumpAndSettle();
    expect(repo.lookups, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('26 Track order: no Sign in prompt for a signed-in customer', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      screen: const GuestTrackOrderScreen(),
      account: _GuestRepo(order: _order('en')),
    );
    expect(find.text('Have an account?'), findsNothing);
  });

  testWidgets('26 Track order: the number from a link is filled in', (
    tester,
  ) async {
    await pumpAudit(
      tester,
      signedIn: false,
      screen: const GuestTrackOrderScreen(initialNumber: ' 000000248 '),
      account: _GuestRepo(order: _order('en')),
    );
    final number = tester.widget<TextField>(find.byType(TextField).first);
    expect(number.controller!.text, '000000248');
  });

  group('orderProgress', () {
    const base = CustomerOrder(number: '1', status: 'Pending', date: '');

    test('a new order has no step filled', () {
      expect(orderProgress(base), 0);
    });

    test('an invoice confirms it', () {
      expect(
        orderProgress(
          const CustomerOrder(
            number: '1',
            status: 'Processing',
            date: '',
            invoiceCount: 1,
          ),
        ),
        1,
      );
    });

    test('a shipment means packed and shipped', () {
      expect(orderProgress(_order('en')), 3);
      expect(
        orderProgress(
          const CustomerOrder(
            number: '1',
            status: 'Processing',
            date: '',
            trackings: [
              OrderTracking(title: 'DHL', number: '123', carrier: 'dhl'),
            ],
          ),
        ),
        3,
      );
    });

    test('a store already processing confirms it, nothing shipped', () {
      expect(
        orderProgress(
          const CustomerOrder(
            number: '1',
            status: 'Processing',
            date: '',
            packages: [
              OrderPackage(
                statusCode: 'processing',
                statusLabel: 'Processing',
                state: 'processing',
              ),
            ],
          ),
        ),
        1,
      );
    });

    test('complete is delivered; cancelled has nothing filled', () {
      expect(
        orderProgress(
          const CustomerOrder(
            number: '1',
            status: 'Complete',
            date: '',
            invoiceCount: 1,
            shipmentCount: 1,
          ),
        ),
        4,
      );
      expect(
        orderProgress(
          const CustomerOrder(
            number: '1',
            status: 'Canceled',
            date: '',
            invoiceCount: 1,
          ),
        ),
        0,
      );
    });
  });
}
