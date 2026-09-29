import '../domain/checkout.dart';
import '../domain/payment_wallet.dart';

/// Payment methods in the CL042-DEV27 display order, stable within a rank.
///
/// Lives here rather than on `CheckoutController` because two screens draw a
/// payment list — the checkout payment step and the post-order complete-payment
/// screen — and the latter takes its methods from a route `extra`, so it must
/// not depend on its caller having sorted them. Same reasoning as
/// [filterUnavailableWallets] in `wallet_availability.dart`, which it composes
/// with at both call sites.
List<PaymentMethodOption> orderPayments(List<PaymentMethodOption> methods) {
  final indexed = methods.asMap().entries.toList()
    ..sort((a, b) {
      final r = paymentRank(a.value.code).compareTo(paymentRank(b.value.code));
      return r != 0 ? r : a.key.compareTo(b.key);
    });
  return [for (final e in indexed) e.value];
}

/// Display order: Apple Pay, Samsung Pay, Visa & MasterCard, Tabby, **Tamara
/// instalments, Tamara Pay Now**, Cash on Delivery (CL042-DEV27, with Tamara
/// placed after Tabby at the client's request 2026-09-28). Check/Money order is
/// not in the client's list, so it sorts below them; anything unknown
/// (including Zero Subtotal `free`, which is normally the only method when it
/// appears) keeps the fallback rank.
///
/// The wallet tests must stay ABOVE the `ngenius` substring test: the wallet
/// method codes are `ngeniusonline_applepay` / `ngeniusonline_samsungpay`, so a
/// substring check would swallow them into the card row's rank and leave their
/// relative order down to whatever the API happened to return.
int paymentRank(String code) {
  final c = code.toLowerCase();
  switch (walletForMethodCode(code)) {
    case PaymentWallet.applePay:
      return 0;
    case PaymentWallet.samsungPay:
      return 1;
    case PaymentWallet.card:
      break;
  }
  if (c.contains('ngenius') || c.contains('network')) return 2;
  if (c.contains('tabby')) return 3;
  // Both Tamara methods sit after Tabby and stay adjacent, instalments first:
  // that is the BNPL offer pairing with Tabby, while Pay Now is pay-in-full.
  // Ranked explicitly rather than left to the order the API returns, which has
  // been observed to move Tamara between first and fourth across requests.
  if (c.contains('tamara')) return c.contains('pay_now') ? 5 : 4;
  if (isCodMethod(c)) return 6;
  if (c.contains('checkmo') || c.contains('check')) return 7;
  return 50;
}

/// Whether [code] is cash on delivery, across the spellings Magento and the
/// common COD extensions use. Shared so the ranking and the checkout default
/// selection cannot drift apart on which codes count as COD.
bool isCodMethod(String code) {
  final c = code.toLowerCase();
  return c.contains('cashondelivery') ||
      c.contains('cash_on_delivery') ||
      c == 'cod';
}
