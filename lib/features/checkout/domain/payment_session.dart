import 'payment_wallet.dart';

/// Normalized payment outcome the checkout flow reasons about, mapped from the
/// native module's canonical status strings (see NativePaymentGateway).
enum PaymentOutcome { success, cancelled, rejected, failed, expired }

/// Which gateway owns a session (the `gateway` field of `paymentSession`).
/// Gateways this build can actually present.
///
/// [unknown] is not a gateway — it is the backend naming one this app does not
/// implement (a method enabled server-side before the app ships support). It
/// exists so an unrecognised name cannot be mistaken for a gateway we do have:
/// routing a foreign session into the N-Genius SDK would show the shopper a
/// card screen for a payment that is not a card.
enum PaymentProvider { ngenius, tabby, tamara, unknown }

/// Lifecycle of a gateway session as reported by the `paymentSession` resolver.
enum PaymentSessionStatus { ready, pending, rejected, failed }

/// The gateway session for an already-placed order, returned by the backend
/// `paymentSession(order_number)` resolver (module `MagentoEgypt_PaymentGraphQl`).
/// Mirrors `PaymentSessionOutput` — see docs/backend/payment-contract.md.
class PaymentSession {
  const PaymentSession({
    required this.orderNumber,
    required this.methodCode,
    required this.gateway,
    required this.status,
    this.paymentId,
    this.webUrl,
    this.publishableKey,
    this.additionalData = const <String, String>{},
  });

  final String orderNumber;

  /// ngeniusonline | ngeniusonline_applepay | ngeniusonline_samsungpay |
  /// tabby_installments | tabby_cc_installments | tabby_checkout.
  final String methodCode;
  final PaymentProvider gateway;
  final PaymentSessionStatus status;

  /// Tabby `payment.id` · N-Genius order reference.
  final String? paymentId;

  /// URL the native layer drives: N-Genius payment-authorization href · Tabby web_url.
  final String? webUrl;

  /// Tabby public key for the native Tabby SDK; null for N-Genius.
  final String? publishableKey;

  /// Raw gateway passthrough (full order JSON, hrefs, outlet ref, selected product…).
  final Map<String, String> additionalData;

  /// Exactly `status == READY` per the contract — only a ready session may be
  /// handed to the native SDK.
  bool get isReady => status == PaymentSessionStatus.ready;

  /// Which native wallet sheet to open. Derived from [methodCode] by the same
  /// function `PaymentMethodOption.wallet` uses, so the checkout row and the
  /// channel argument can never disagree.
  PaymentWallet get wallet => walletForMethodCode(methodCode);
}
