import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/account/data/account_repository.dart';
import 'package:hubmarket_app/features/account/domain/order.dart';
import 'package:hubmarket_app/features/checkout/payments/tamara_settlement.dart';

import '../../support/fakes.dart';

/// Only ever consulted after the customer dismissed the Tamara sheet without a
/// verdict. It may upgrade that to success — never the other way — and only on
/// an invoice, which is a fact rather than a translated status label.
class _Repo implements AccountRepository {
  _Repo({this.invoiced = false, this.fail = false});

  final bool invoiced;
  final bool fail;
  int tokenLookups = 0;
  int customerLookups = 0;

  CustomerOrder _order(String number) => CustomerOrder(
    number: number,
    status: 'Pending Payment',
    date: '2026-09-28',
    invoiceCount: invoiced ? 1 : 0,
  );

  @override
  Future<CustomerOrder> fetchGuestOrderByToken(String token) async {
    tokenLookups++;
    if (fail) throw const Failure(FailureKind.server);
    return _order('2000000700');
  }

  @override
  Future<OrderPage> fetchOrders({
    int pageSize = 10,
    int currentPage = 1,
  }) async {
    customerLookups++;
    if (fail) throw const Failure(FailureKind.server);
    return OrderPage(
      items: [_order('2000000700')],
      currentPage: 1,
      totalPages: 1,
      totalCount: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<bool> _probe(WidgetTester tester, _Repo repo, String number) async {
  late WidgetRef capturedRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        localCacheProvider.overrideWithValue(FakeLocalCache()),
      ],
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) {
            capturedRef = ref;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  final future = tamaraOrderSettled(capturedRef, number);
  // Drive the backoff without waiting in real time.
  await tester.pump(const Duration(seconds: 10));
  return future;
}

void main() {
  testWidgets('reports settled when the order has been invoiced', (
    tester,
  ) async {
    final repo = _Repo(invoiced: true);
    expect(await _probe(tester, repo, '2000000700'), isTrue);
  });

  testWidgets('reports not settled while no invoice exists', (tester) async {
    // The honest answer for an order that really was abandoned: the customer
    // goes to CompletePaymentScreen rather than getting a confirmation.
    final repo = _Repo();
    expect(await _probe(tester, repo, '2000000700'), isFalse);
  });

  testWidgets('reports not settled when the lookup fails', (tester) async {
    // A probe that cannot read the order must never be read as payment.
    final repo = _Repo(invoiced: true, fail: true);
    expect(await _probe(tester, repo, '2000000700'), isFalse);
  });

  testWidgets('does not call out at all for an empty order number', (
    tester,
  ) async {
    final repo = _Repo(invoiced: true);
    expect(await _probe(tester, repo, ''), isFalse);
    expect(repo.customerLookups, 0);
    expect(repo.tokenLookups, 0);
  });
}
