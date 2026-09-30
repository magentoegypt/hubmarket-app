import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../../../core/util/store_time.dart';
import '../../account/data/account_repository.dart';
import '../../account/domain/order.dart';
import '../../auth/presentation/auth_controller.dart';

/// How many of the customer's newest orders the Home looks at.
const int kActiveOrderLookback = 3;

/// How long an open order stays "recent" enough for the Home card.
const Duration kActiveOrderWindow = Duration(days: 30);

/// The order the Home's card is about: the newest of [orders] (newest first)
/// that is neither complete / delivered nor cancelled / closed, placed within
/// [kActiveOrderWindow] of [now]. Null when there is none.
CustomerOrder? pickActiveOrder(
  Iterable<CustomerOrder> orders, {
  required DateTime now,
}) {
  for (final order in orders) {
    if (order.isDelivered || order.isCancelled) continue;
    // Store wall-clock read as device time: a few hours either way don't
    // matter against the window.
    final placed = storeStampToLocal(order.date, '');
    if (placed == null || now.difference(placed) > kActiveOrderWindow) {
      continue;
    }
    return order;
  }
  return null;
}

/// The signed-in customer's active order for the Home (Figma 07 "Active
/// order"), from core `customer.orders`: one small query for the
/// [kActiveOrderLookback] newest, kept for the session. The Home's
/// pull-to-refresh invalidates it; signing in or out and a store switch read
/// it again.
///
/// Null for a guest, when no recent order is still open, and on any failure
/// — the card then isn't drawn, and the Home never fails over it.
final activeOrderProvider = FutureProvider<CustomerOrder?>((ref) async {
  final signedIn = ref.watch(
    authControllerProvider.select((s) => s.isAuthenticated),
  );
  if (!signedIn) return null;
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  try {
    final orders = await ref
        .watch(accountRepositoryProvider)
        .fetchRecentOrders(pageSize: kActiveOrderLookback);
    return pickActiveOrder(orders, now: DateTime.now());
  } on Object {
    return null;
  }
});
