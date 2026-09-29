import '../../catalog/domain/money.dart';
import 'payment_wallet.dart';
import 'tabby_config.dart';

class ShippingMethodOption {
  const ShippingMethodOption({
    required this.carrierCode,
    required this.methodCode,
    required this.title,
    this.amount,
  });

  final String carrierCode;
  final String methodCode;
  final String title;
  final Money? amount;

  String get id => '$carrierCode|$methodCode';
}

class PaymentMethodOption {
  const PaymentMethodOption({required this.code, required this.title});

  final String code;
  final String title;

  /// Which native wallet sheet this method opens — Apple Pay / Samsung Pay ride
  /// the same N-Genius session as the card form, so they are a wallet, not a
  /// gateway. See [walletForMethodCode].
  PaymentWallet get wallet => walletForMethodCode(code);

  bool get isApplePay => wallet == PaymentWallet.applePay;
  bool get isSamsungPay => wallet == PaymentWallet.samsungPay;
  bool get isWallet => wallet != PaymentWallet.card;

  /// Redirect (off-site) gateways need the native payment SDK / session flow.
  /// Detected by well-known method codes; the redirect URL itself comes from the
  /// gateway extension (Open Q §2).
  ///
  /// The wallet short-circuit is load-bearing, not a convenience: the backend
  /// wallet codes are provisional, and if one of them ever lacked an `ngenius`
  /// substring this would return false and `_placeOrder` would route the shopper
  /// to order-success with no session and no payment taken. `free`, COD and
  /// checkmo cannot normalise to contain `applepay`/`samsungpay`, so the
  /// non-gateway path is unaffected.
  bool get isRedirect {
    if (isWallet) return true;
    final c = code.toLowerCase();
    return c.contains('ngenius') ||
        c.contains('network_international') ||
        c.contains('tabby') ||
        c.contains('tamara');
  }

  bool get isTabby => code.toLowerCase().contains('tabby');

  /// Tamara (`tamara_pay_by_instalments`) — BNPL, like Tabby, and therefore a
  /// redirect method. It must never fall through to the non-gateway path: the
  /// backend served it before `PaymentGateway` gained a `TAMARA` value, and
  /// while it read as non-redirect the app finalised on `placeOrder` and showed
  /// order success with nothing paid.
  bool get isTamara => code.toLowerCase().contains('tamara');

  /// Magento's vault code for N-Genius saved cards (`ngeniusonline_vault`),
  /// mirroring core `payflowpro_cc_vault`. The backend advertises it in
  /// `available_payment_methods` only when the customer actually has a stored
  /// token — the app never injects it.
  ///
  /// It is not rendered as its own row: checkout nests the saved cards under
  /// the ordinary card row (see `CheckoutState.visiblePaymentMethods`), so a
  /// shopper with four cards still sees one "Visa & MasterCard" entry.
  bool get isCardVault {
    final c = code.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
    return c.contains('ngenius') && c.contains('vault');
  }

  /// The plain N-Genius card row — the one the saved-card picker hangs under.
  /// Excludes the wallets (which ride the same gateway) and the vault code.
  bool get isCard =>
      !isWallet && !isCardVault && !isTabby &&
      (code.toLowerCase().contains('ngenius') ||
          code.toLowerCase().contains('network_international'));

  /// Magento's **Zero Subtotal Checkout** (`free`) — surfaced only when the cart
  /// grand total is 0 (e.g. fully covered by a coupon or 100%-off items). It has
  /// no gateway: `placeOrder` completes the order as paid immediately, so it
  /// falls into the non-redirect, instant-success path at checkout.
  bool get isFree => code.toLowerCase() == 'free';

  /// Which Tabby product this method is, so checkout labels it correctly.
  /// Codes: tabby_cc_installments → card instalments; tabby_checkout → pay later;
  /// tabby_installments (or any other tabby) → pay in 4.
  TabbyProductType? get tabbyProduct {
    final c = code.toLowerCase();
    if (!c.contains('tabby')) return null;
    if (c.contains('cc_installments') || c.contains('credit')) {
      return TabbyProductType.creditCardInstallments;
    }
    if (c.contains('checkout') || c.contains('later')) {
      return TabbyProductType.payLater;
    }
    return TabbyProductType.installments;
  }
}

class PlaceOrderResult {
  const PlaceOrderResult({required this.orderNumber, this.orderToken});

  final String orderNumber;

  /// Guest order token (`placeOrder.orderV2.token`, Magento 2.4.7+) — passed to
  /// `paymentSession(... token:)` to authorize a guest's follow-up payment call
  /// (the live resolver's `token` arg). Null for logged-in customers (the
  /// bearer authorizes).
  final String? orderToken;
}
