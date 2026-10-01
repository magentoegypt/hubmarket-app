import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/domain/money.dart';
import '../../returns/data/returns_repository.dart';
import '../../returns/domain/returns.dart';
import '../../returns/presentation/returns_providers.dart';
import '../data/account_repository.dart';
import '../domain/order.dart';

/// What the Account hub (Figma 20) says about the customer's orders, counted
/// and summed from the order history itself — nothing is invented: a figure the
/// history cannot give exactly is left out, and so is the card it belongs to.
@immutable
class AccountOrdersOverview {
  const AccountOrdersOverview({required this.activeCount, this.stats});

  /// Orders neither delivered nor cancelled — the Orders tile's "2 active".
  final int activeCount;

  /// The "Shopping stats" card; null when the whole history could not be read
  /// (more orders than [kOverviewMaxOrders], or no order to speak of).
  final ShoppingStats? stats;
}

/// The three figures of the "Shopping stats" card.
@immutable
class ShoppingStats {
  const ShoppingStats({
    required this.totalSpent,
    required this.ordersThisYear,
    required this.averageOrder,
  });

  /// The grand totals of every order that was not cancelled or refunded.
  final Money totalSpent;

  /// Orders (not cancelled) placed in the current calendar year.
  final int ordersThisYear;

  /// [totalSpent] over the orders it adds up.
  final Money averageOrder;
}

/// Orders read for the overview, in pages of [_digestPage]; beyond this many
/// the history is not read whole and the stats card stays out rather than
/// show a partial sum.
const int kOverviewMaxOrders = 200;
const int _digestPage = 50;

/// Counts and sums [orders] (newest first, as the digest query returns them)
/// for the hub. [complete] says [orders] is the customer's whole history;
/// [year] is the current calendar year.
///
/// A cancelled or refunded order (`CustomerOrder.isCancelled`, the Orders
/// screen's own test) spends nothing and is not an order the customer
/// "placed" for the stats; every order in any currency other than the first
/// one's leaves the stats out (one market, one currency).
AccountOrdersOverview summariseOrders(
  List<CustomerOrder> orders, {
  required bool complete,
  required int year,
}) {
  final active = orders.where((o) => !o.isDelivered && !o.isCancelled).length;
  if (!complete) return AccountOrdersOverview(activeCount: active);

  final counted = [
    for (final order in orders)
      if (!order.isCancelled && order.total != null) order,
  ];
  if (counted.isEmpty) return AccountOrdersOverview(activeCount: active);
  final currency = counted.first.total!.currency;
  if (counted.any((o) => o.total!.currency != currency)) {
    return AccountOrdersOverview(activeCount: active);
  }
  final spent = counted.fold<double>(0, (sum, o) => sum + o.total!.amount);
  final thisYear = counted.where((o) => _yearOf(o.date) == year).length;
  return AccountOrdersOverview(
    activeCount: active,
    stats: ShoppingStats(
      totalSpent: Money(amount: spent, currency: currency),
      ordersThisYear: thisYear,
      averageOrder: Money(amount: spent / counted.length, currency: currency),
    ),
  );
}

/// The year of an order's `order_date` ("2026-09-28 10:42:00"); null when it
/// does not read as one.
int? _yearOf(String stamp) =>
    stamp.length < 4 ? null : int.tryParse(stamp.substring(0, 4));

/// The signed-in customer's [AccountOrdersOverview]: the whole history in
/// light pages (one request for most customers), re-read on a store switch.
/// Null for a guest and on any failure — the hub then hides what it feeds
/// and never fails over it.
final accountOrdersOverviewProvider =
    FutureProvider.autoDispose<AccountOrdersOverview?>((ref) async {
      if (!ref.watch(authControllerProvider).isAuthenticated) return null;
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      try {
        final repository = ref.watch(accountRepositoryProvider);
        final orders = <CustomerOrder>[];
        var total = 0;
        for (var page = 1; ; page++) {
          final result = await repository.fetchOrderDigests(
            pageSize: _digestPage,
            currentPage: page,
          );
          orders.addAll(result.items);
          total = result.totalCount;
          if (page >= result.totalPages || orders.length >= kOverviewMaxOrders) {
            break;
          }
        }
        return summariseOrders(
          orders,
          complete: orders.length >= total,
          year: DateTime.now().year,
        );
      } on Object {
        return null;
      }
    });

/// How many of the customer's newest returns are still open (the Returns
/// tile's "1 open"). Null when the store takes no returns in the app, and on
/// any failure.
final openReturnsCountProvider = FutureProvider.autoDispose<int?>((ref) async {
  if (!ref.watch(returnsAvailableProvider)) return null;
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  try {
    final page = await ref.watch(returnsRepositoryProvider).fetchReturns();
    return page.items.where((r) => r.state == ReturnState.open).length;
  } on Object {
    return null;
  }
});
