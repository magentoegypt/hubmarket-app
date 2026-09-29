import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/store_features.dart';
import '../data/account_repository.dart';
import '../domain/order.dart';

/// Whether an order screen offers "Cancel order": the store has cancellation
/// switched on with at least one reason (storeConfig), and Magento lists
/// `CANCEL` among the order's `available_actions` — it isn't complete,
/// closed, cancelled or on hold, and nothing has shipped.
///
/// Live today (29 Sep 2026) `order_cancellation_enabled` is false in both
/// store views, so the button stays hidden until an admin turns it on under
/// Stores › Configuration › Sales › Order Cancellation.
bool offersOrderCancel(StoreFeatures features, CustomerOrder order) =>
    features.canCancelOrders && order.offersCancel;

/// What a cancellation achieved.
sealed class CancelOutcome {
  const CancelOutcome();
}

/// A customer's order is cancelled; [order] is Magento's updated copy (null
/// when the response carried none).
class OrderCancelled extends CancelOutcome {
  const OrderCancelled(this.order);
  final CustomerOrder? order;
}

/// A guest's request went through: Magento e-mailed the link that confirms
/// it. The order itself is unchanged until then.
class CancellationEmailSent extends CancelOutcome {
  const CancellationEmailSent();
}

/// Cancels [order] for [reason] with the call that fits who placed it: core
/// `cancelOrder` for a signed-in customer's order, `requestGuestOrderCancel`
/// (by the order token) for a guest's. Throws the repository's `Failure` —
/// a refusal carries the store's own message.
Future<CancelOutcome> cancelOrder(
  WidgetRef ref,
  CustomerOrder order,
  String reason,
) async {
  final repo = ref.read(accountRepositoryProvider);
  if (order.placedAsGuest) {
    await repo.requestGuestOrderCancel(token: order.token!, reason: reason);
    return const CancellationEmailSent();
  }
  final updated = await repo.cancelOrder(orderId: order.id, reason: reason);
  // The list shows the status too.
  ref.invalidate(ordersControllerProvider);
  return OrderCancelled(updated);
}
