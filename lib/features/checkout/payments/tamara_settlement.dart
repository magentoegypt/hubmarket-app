import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/payment_trace.dart';
import '../../account/data/account_repository.dart';
import '../../account/data/guest_order_store.dart';
import '../../account/domain/order.dart';

/// How often and how long to ask whether a Tamara order has settled.
///
/// Short on purpose. This runs only when the customer closed the payment sheet
/// before the return page loaded, so it is a best-effort upgrade, not a wait
/// the customer should sit through — if it does not resolve quickly they go to
/// CompletePaymentScreen, which shows the real state anyway.
const List<Duration> _kTamaraPollBackoff = [
  Duration(milliseconds: 800),
  Duration(milliseconds: 1500),
  Duration(seconds: 2),
  Duration(seconds: 3),
];

/// Whether a Tamara order has actually been paid, after the payment sheet was
/// dismissed without a verdict.
///
/// **Why this exists.** Magento reconciles with Tamara while serving the
/// `…/success` return page. If the customer closes the sheet first that never
/// runs — but Tamara's server-to-server notification
/// (`tamara/payment/notification`) reconciles independently, a moment later.
/// So a dismissal is not proof of non-payment, and reporting "cancelled" to
/// someone who just paid is the thing this softens.
///
/// **Why invoices and not status.** The backend's guidance is to poll the order
/// state, but `CustomerOrder` exposes no `state` field — only `status`, which
/// is a **localized label** (the Arabic store view returns Arabic). Deciding
/// whether money moved by matching translated strings is not sound. An invoice
/// is a fact: Magento raises one when payment is captured, and `invoices` is
/// already in the order selection.
///
/// **It can only upgrade, never downgrade.** A false negative sends the
/// customer to CompletePaymentScreen, where the real state is resolved. A false
/// positive would hand out a confirmation for money that never moved, so the
/// only thing treated as proof is an invoice that exists.
///
/// Returns false on every error, timeout, or order it cannot read.
Future<bool> tamaraOrderSettled(WidgetRef ref, String orderNumber) async {
  if (orderNumber.isEmpty) return false;
  for (final delay in _kTamaraPollBackoff) {
    await Future<void>.delayed(delay);
    final order = await _readOrder(ref, orderNumber);
    if (order == null) continue;
    if (order.hasInvoice) {
      PaymentTrace.record('tamara: order $orderNumber invoiced → settled');
      return true;
    }
  }
  PaymentTrace.record(
    'tamara: order $orderNumber not invoiced within poll → awaiting payment',
  );
  return false;
}

/// Reads the order by whichever route this customer has.
///
/// A guest has no bearer, so the lookup goes through the ref persisted at
/// checkout — the same one `/orders` uses. Every failure is swallowed: this is
/// a best-effort probe and must never turn into an error the customer sees.
Future<CustomerOrder?> _readOrder(WidgetRef ref, String orderNumber) async {
  final repo = ref.read(accountRepositoryProvider);
  try {
    final guest = _guestRef(ref, orderNumber);
    if (guest != null) {
      if (guest.hasToken) return await repo.fetchGuestOrderByToken(guest.token!);
      final email = guest.email;
      final lastname = guest.lastname;
      if (email != null && lastname != null) {
        return await repo.fetchGuestOrder(
          number: orderNumber,
          email: email,
          lastname: lastname,
        );
      }
      return null;
    }
    // Signed in: the order was just placed, so it is on the first page.
    final page = await repo.fetchOrders(pageSize: 5, currentPage: 1);
    for (final order in page.items) {
      if (order.number == orderNumber) return order;
    }
    return null;
  } on Object {
    return null;
  }
}

GuestOrderRef? _guestRef(WidgetRef ref, String orderNumber) {
  for (final candidate in ref.read(guestOrderStoreProvider)) {
    if (candidate.number == orderNumber) return candidate;
  }
  return null;
}
