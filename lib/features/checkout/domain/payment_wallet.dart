/// Which native wallet sheet a payment method opens.
///
/// This is deliberately NOT "which brand is this method" — Tabby has its own
/// `isTabby` flag and no wallet sheet. It answers only: when the session is
/// handed to the native `hubmarket/payments` module, which SDK entry point runs.
///
/// Apple Pay and Samsung Pay are **N-Genius wallet flows, not new gateways**:
/// they authorize the same N-Genius order the card path uses, so
/// [PaymentProvider] gains no value and every exhaustive switch over it is
/// untouched. Only the Magento `method_code` differs.
enum PaymentWallet {
  card,
  applePay,
  samsungPay;

  /// The exact string the native side switches on (contract §③).
  String get wire => switch (this) {
    PaymentWallet.card => 'card',
    PaymentWallet.applePay => 'applepay',
    PaymentWallet.samsungPay => 'samsungpay',
  };
}

/// Maps a Magento payment method code to its wallet.
///
/// Matching is loose *on purpose*, and it already earned its keep: the contract
/// was written against an assumed `ngenius_applepay`, and the backend shipped
/// `ngeniusonline_applepay` (live-confirmed 2026-08-20). An exact match would
/// have failed silently, and the cost of a miss is severe — a wallet code that
/// isn't recognised falls out of `PaymentMethodOption.isRedirect`, and checkout
/// would show a success screen for an order nobody paid for. So the separators
/// are stripped first and the rest is a substring test, which absorbs
/// `ngeniusonline_applepay`, `ngenius_apple_pay`, `apple-pay`, `applepay`,
/// `ngeniusApplePay` and the Samsung equivalents alike.
///
/// Note this normalisation is NOT reused by `tabbyProduct`, which matches
/// `cc_installments` with its underscores intact.
PaymentWallet walletForMethodCode(String code) {
  final c = code.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  if (c.contains('applepay')) return PaymentWallet.applePay;
  if (c.contains('samsungpay')) return PaymentWallet.samsungPay;
  return PaymentWallet.card;
}
