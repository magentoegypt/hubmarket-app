import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../domain/checkout.dart';
import '../domain/payment_wallet.dart';
import '../domain/tabby_config.dart';

/// Selectable payment-method card with the brand mark, product subtitle and
/// Tabby chip.
/// Shared by the checkout payment step and the post-order complete-payment screen.
class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
    this.child,
  });

  final PaymentMethodOption method;
  final bool selected;
  final VoidCallback onTap;

  /// Rendered inside the card, under the row — the saved-card picker on the
  /// N-Genius card method. Kept in the same [Card] so a chosen saved card reads
  /// as part of that method rather than as a sibling option.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.brandPrimary : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _row(context, l10n),
          if (child != null) child!,
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppLocalizations l10n) => ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? AppColors.brandPrimary : AppColors.inkMuted,
        ),
        title: Row(
          children: [
            _methodMark(context, method),
            const SizedBox(width: 10),
            Expanded(child: Text(method.title)),
          ],
        ),
        subtitle: _subtitle(l10n),
        trailing: method.isTabby
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3EE6C3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'tabby',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
      );

  /// The brand mark for Apple Pay / Samsung Pay, or the Material icon for
  /// everything else.
  ///
  /// Apple's marketing guidelines require the *official* Apple Pay mark: it may
  /// not be recreated, recoloured, or replaced with a logo glyph — so
  /// `Icons.apple` is not an acceptable stand-in on a payment screen. Samsung's
  /// Wallet guidelines are the same in spirit. Until the licensed artwork is
  /// dropped into `assets/payments/`, `errorBuilder` falls back to the Material
  /// icon so the row still renders rather than showing a broken image.
  Widget _methodMark(BuildContext context, PaymentMethodOption m) {
    final asset = switch (m.wallet) {
      PaymentWallet.applePay => 'apple_pay_mark',
      PaymentWallet.samsungPay => 'samsung_pay_mark',
      PaymentWallet.card => null,
    };
    if (asset == null) {
      return Icon(_methodIcon(m), size: 20, color: AppColors.inkHeading);
    }
    // The marks ship dark-on-light and white-on-dark; the row sits on the card
    // surface, so follow the theme rather than the scaffold.
    final variant = Theme.of(context).brightness == Brightness.dark
        ? '_white'
        : '';
    return Image.asset(
      'assets/payments/$asset$variant.png',
      height: 20,
      errorBuilder: (context, error, stack) =>
          Icon(_methodIcon(m), size: 20, color: AppColors.inkHeading),
    );
  }

  /// A representative icon per method (QA: "add the appropriate icons").
  IconData _methodIcon(PaymentMethodOption m) {
    if (m.isFree) return Icons.card_giftcard;
    if (m.isTabby) return Icons.calendar_today_outlined;
    // Above the `ngenius` test below, which would otherwise swallow
    // `ngeniusonline_applepay` and render a plain credit card.
    if (m.isApplePay) return Icons.account_balance_wallet_outlined;
    if (m.isSamsungPay) return Icons.account_balance_wallet_outlined;
    final c = m.code.toLowerCase();
    if (c.contains('checkmo') || c.contains('check')) {
      return Icons.request_quote_outlined;
    }
    if (c.contains('cashondelivery') ||
        c.contains('cash_on_delivery') ||
        c == 'cod') {
      return Icons.payments_outlined;
    }
    if (c.contains('ngenius') || c.contains('network')) {
      return Icons.credit_card_outlined;
    }
    return Icons.account_balance_wallet_outlined;
  }

  /// Subtitle copy: the friendly "no payment needed" line for Zero Subtotal
  /// Checkout (`free`), otherwise the Tabby product line, otherwise none.
  Widget? _subtitle(AppLocalizations l10n) {
    if (method.isFree) return Text(l10n.checkoutFreeOrder);
    if (method.isApplePay) return Text(l10n.checkoutApplePaySubtitle);
    if (method.isSamsungPay) return Text(l10n.checkoutSamsungPaySubtitle);
    return switch (method.tabbyProduct) {
      TabbyProductType.installments => Text(l10n.checkoutPayIn4),
      TabbyProductType.payLater => Text(l10n.checkoutPayLater),
      TabbyProductType.creditCardInstallments => Text(
        l10n.checkoutCardInstalments,
      ),
      null => null,
    };
  }
}
