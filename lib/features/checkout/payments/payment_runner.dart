import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/diagnostics/payment_trace.dart';
import '../../catalog/domain/money.dart';
import '../domain/payment_session.dart';
import 'payment_gateway.dart';
import 'tamara_settlement.dart';

/// What happened when we tried to drive a session to payment.
enum PaymentStep { presented, pending, rejected, failed, unavailable }

class PaymentRunResult {
  const PaymentRunResult(this.step, [this.outcome]);

  final PaymentStep step;

  /// The native-SDK outcome when [step] is [PaymentStep.presented].
  final PaymentOutcome? outcome;
}

/// Resolves the gateway for a READY session and presents it, normalising the
/// session status and the native outcome into one result the caller can act on.
/// Shared by the initial checkout flow and the post-order retry screen so both
/// route consistently. `unavailable` = no session / not launchable / native
/// module missing → the order stays awaiting payment (never a fake success).
Future<PaymentRunResult> runPaymentSession({
  required BuildContext context,
  required WidgetRef ref,
  required PaymentSession? session,
  Money? amount,
}) async {
  if (session == null) {
    // Already traced by fetchPaymentSession, but record the consequence so the
    // trail shows why the customer saw "awaiting payment".
    PaymentTrace.record('run: no session → awaiting payment');
    return const PaymentRunResult(PaymentStep.unavailable);
  }
  switch (session.status) {
    case PaymentSessionStatus.ready:
      final gateway = ref.read(paymentGatewayResolverProvider).resolve(session);
      if (gateway == null) {
        PaymentTrace.record(
          'run: no gateway for ${session.gateway.name} → awaiting payment',
        );
        return const PaymentRunResult(PaymentStep.unavailable);
      }
      try {
        PaymentTrace.record('run: presenting ${session.gateway.name}');
        var outcome = await gateway.present(context, session, amount: amount);
        PaymentTrace.record('run: outcome ${outcome.name}');
        // Tamara only: a dismissal is not proof of non-payment. Magento
        // reconciles while serving the return page, so closing the sheet first
        // skips that — but Tamara's server-to-server notification reconciles
        // anyway, a moment later. Ask the order before telling someone who just
        // paid that they did not. Only ever upgrades, and only on an invoice.
        if (session.gateway == PaymentProvider.tamara &&
            outcome == PaymentOutcome.cancelled) {
          if (await tamaraOrderSettled(ref, session.orderNumber)) {
            PaymentTrace.record('run: tamara settled after dismissal → success');
            outcome = PaymentOutcome.success;
          }
        }
        return PaymentRunResult(PaymentStep.presented, outcome);
      } on PaymentGatewayUnavailable {
        // The native module is missing or unregistered — distinct from a bad
        // session, and previously indistinguishable from it.
        PaymentTrace.record(
          'run: NATIVE MODULE MISSING for ${session.gateway.name}',
        );
        return const PaymentRunResult(PaymentStep.unavailable);
      }
    case PaymentSessionStatus.pending:
      PaymentTrace.record('run: session PENDING after retries');
      return const PaymentRunResult(PaymentStep.pending);
    case PaymentSessionStatus.rejected:
      PaymentTrace.record('run: session REJECTED by gateway');
      return const PaymentRunResult(PaymentStep.rejected);
    case PaymentSessionStatus.failed:
      PaymentTrace.record('run: session FAILED');
      return const PaymentRunResult(PaymentStep.failed);
  }
}
