import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/store/store_urls.dart';
import '../../catalog/domain/money.dart';
import '../domain/payment_session.dart';
import 'native_payment_gateway.dart';
import 'tabby_payment_gateway.dart';
import 'tamara_payment_gateway.dart';

/// Thrown when the native payment module isn't installed yet. The caller treats
/// this as "couldn't present" → the order stays awaiting payment (not a failure
/// blamed on the customer, and never a fabricated success).
class PaymentGatewayUnavailable implements Exception {
  const PaymentGatewayUnavailable();
}

/// Hands a ready session to the native gateway SDK and resolves the outcome.
abstract interface class PaymentGateway {
  Future<PaymentOutcome> present(
    BuildContext context,
    PaymentSession session, {
    Money? amount,
  });
}

/// Routes a ready session to the gateway that owns it. A non-ready session
/// resolves to null and the caller routes by status (pending → awaiting
/// payment; rejected/failed → back to method selection).
///
/// The three gateways are integrated differently and deliberately so: N-Genius
/// has no Flutter package, so it goes through the native `hubmarket/payments`
/// module; Tabby publishes an official Flutter package, so it stays in Dart;
/// Tamara publishes neither, but its session carries a hosted-checkout
/// `web_url`, so it renders in a WebView and reads the outcome from the return
/// to the store's domain.
///
/// Apple Pay and Samsung Pay do **not** appear here. They are N-Genius wallet
/// flows on the same session, selected by `PaymentSession.wallet` inside the
/// native gateway — so this switch stays two-valued and every other exhaustive
/// switch over [PaymentProvider] is untouched.
class PaymentGatewayResolver {
  const PaymentGatewayResolver({
    required this.native,
    required this.tabby,
    required this.tamara,
  });

  final PaymentGateway native;
  final PaymentGateway tabby;
  final PaymentGateway tamara;

  PaymentGateway? resolve(PaymentSession session) {
    if (!session.isReady) return null;
    return switch (session.gateway) {
      PaymentProvider.tabby => tabby,
      PaymentProvider.tamara => tamara,
      PaymentProvider.ngenius => native,
      // A gateway this build cannot present — the caller treats a null the same
      // as a non-ready session and leaves the order awaiting payment.
      PaymentProvider.unknown => null,
    };
  }
}

final paymentGatewayResolverProvider = Provider<PaymentGatewayResolver>((ref) {
  // Tamara returns the customer to the store's own domain when it is done, so
  // the gateway needs to know what that domain is. Taken from the resolved
  // store view rather than AppConfig's GraphQL endpoint, which is the API host
  // and need not be the storefront's.
  final base = storeBaseUrl(ref.watch(storeControllerProvider));
  return PaymentGatewayResolver(
    native: NativePaymentGateway(config: ref.watch(appConfigProvider)),
    tabby: const TabbyPaymentGateway(),
    tamara: TamaraPaymentGateway(host: Uri.tryParse(base)?.host ?? ''),
  );
});
