import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../domain/checkout.dart';

/// Selectable payment-method card: radio, method icon and title.
class PaymentMethodCard extends StatelessWidget {
  const PaymentMethodCard({
    super.key,
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethodOption method;
  final bool selected;
  final VoidCallback onTap;

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
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: selected ? AppColors.brandPrimary : AppColors.inkMuted,
        ),
        title: Row(
          children: [
            Icon(_methodIcon(method), size: 20, color: AppColors.inkHeading),
            const SizedBox(width: 10),
            Expanded(child: Text(method.title)),
          ],
        ),
        // The friendly "no payment needed" line for Zero Subtotal Checkout.
        subtitle: method.isFree ? Text(l10n.checkoutFreeOrder) : null,
      ),
    );
  }

  /// A representative icon per method (QA: "add the appropriate icons").
  IconData _methodIcon(PaymentMethodOption m) {
    if (m.isFree) return Icons.card_giftcard;
    if (m.isCashOnDelivery) return Icons.payments_outlined;
    final c = m.code.toLowerCase();
    if (c.contains('checkmo') || c.contains('check')) {
      return Icons.request_quote_outlined;
    }
    return Icons.account_balance_wallet_outlined;
  }
}
