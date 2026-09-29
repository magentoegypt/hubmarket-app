import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../core/config/app_config.dart';
import '../../../core/diagnostics/payment_trace.dart';
import '../../catalog/domain/money.dart';
import '../domain/payment_session.dart';
import 'payment_gateway.dart';

/// Bridges to the platform-native payment SDKs over the `hubmarket/payments`
/// MethodChannel — N-Genius (`payment-sdk-android` / `NISdk`) and Tabby. The
/// native module launches the SDK, waits for its delegate/callback, and returns
/// a result map with a canonical `status` string (docs/backend/payment-contract.md).
class NativePaymentGateway implements PaymentGateway {
  /// [AppConfig.current] is a `static const`, so this stays a valid `const`
  /// default and every existing `const NativePaymentGateway()` keeps compiling.
  const NativePaymentGateway({this.config = AppConfig.current});

  /// Supplies the wallet merchant identifiers (see [AppConfig.walletIdentifierArgs]).
  final AppConfig config;

  static const MethodChannel channel = MethodChannel('hubmarket/payments');

  @override
  Future<PaymentOutcome> present(
    BuildContext context,
    PaymentSession session, {
    Money? amount,
  }) async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('pay', {
        'gateway': session.gateway == PaymentProvider.tabby
            ? 'tabby'
            : 'ngenius',
        // Apple Pay / Samsung Pay are N-Genius *wallets*, not gateways: the
        // gateway stays `ngenius` so the native module's existing gateway guard
        // (which lets Tabby fall through to Dart) is untouched, and only this
        // key selects the SDK entry point.
        'wallet': session.wallet.wire,
        'methodCode': session.methodCode,
        'orderNumber': session.orderNumber,
        // Renders the gateway SDK's own UI in the customer's language.
        'language': Localizations.localeOf(context).languageCode,
        if (amount != null) 'amount': amount.amount,
        // Apple Pay charges what it is given. `amount` crosses the channel as a
        // double, and 199.00 round-trips through binary floating point as
        // 199.00000000000003 — which PassKit would display AND charge. The
        // decimal string is authoritative; `amount` stays for the card path.
        if (amount != null) 'amountString': amount.amount.toStringAsFixed(2),
        if (amount != null) 'currency': amount.currency,
        ...config.walletIdentifierArgs,
        // N-Genius: iOS decodes the full order JSON; Android drives the links.
        'orderResponse': session.additionalData['order_response'],
        // Two different links, and swapping them makes the SDK authorize
        // against the pay page and get back an HTML error page.
        //   authorization_href → _links.payment-authorization (authorize here)
        //   pay_page_href      → _links.payment (hosted page, carries ?code=)
        // `payment_authorization_href` is the old, misnamed key: it carried the
        // pay-page href. Read only as a last resort, and never as the
        // authorization link.
        'authorizationHref': session.additionalData['authorization_href'],
        'payPageHref':
            session.additionalData['pay_page_href'] ??
            session.additionalData['payment_authorization_href'] ??
            session.webUrl,
        'outletRef': session.additionalData['outlet_ref'],
        // Tabby: SDK webview on both platforms.
        'webUrl': session.webUrl,
        'publishableKey': session.publishableKey,
        'paymentId': session.paymentId,
      });
      // The native module's own status/reason, which the PaymentOutcome enum
      // cannot carry. Without it a gateway decline, an expired session and an
      // SDK error all arrive as plain "failed".
      PaymentTrace.record(
        'native: wallet=${session.wallet.wire} status=${result?['status']} '
        'reference=${result?['reference']} raw=${result?['raw'] ?? "none"}',
      );
      return _mapStatus(result?['status'] as String?);
    } on MissingPluginException {
      throw const PaymentGatewayUnavailable();
    } on PlatformException catch (error) {
      PaymentTrace.record(
        'native: PlatformException ${error.code} — ${error.message}',
      );
      return PaymentOutcome.failed;
    }
  }

  /// Maps the native module's canonical status string (see the contract table).
  PaymentOutcome _mapStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'SUCCESS':
      case 'AUTHORISED':
      case 'AUTHORIZED':
      case 'CAPTURED':
      case 'PURCHASED':
      // Post-auth review: order placed, captured asynchronously → treat as success
      // (the app re-queries order status afterwards).
      case 'POST_AUTH_REVIEW':
      case 'PAYMENT_POST_AUTH_REVIEW':
        return PaymentOutcome.success;
      case 'CANCELLED':
      case 'CANCELED':
      case 'ABORTED':
      case 'CLOSED':
        return PaymentOutcome.cancelled;
      case 'DECLINED':
      case 'AUTH_FAILED':
      case 'THREE_DS_FAILURE':
      case 'REJECTED':
        return PaymentOutcome.rejected;
      case 'EXPIRED':
        return PaymentOutcome.expired;
      default:
        return PaymentOutcome.failed;
    }
  }
}
