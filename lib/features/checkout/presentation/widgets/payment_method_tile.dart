import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/checkout.dart';
import 'checkout_parts.dart';

/// A representative icon per payment method — shared by the payment step, the
/// review card and the order-placed screen.
IconData paymentMethodIcon(PaymentMethodOption method) {
  if (method.isFree) return Icons.card_giftcard;
  if (method.isCashOnDelivery) return Icons.payments_outlined;
  final c = method.code.toLowerCase();
  if (c.contains('checkmo')) return Icons.request_quote_outlined;
  if (c.contains('banktransfer')) return Icons.account_balance_outlined;
  return Icons.account_balance_wallet_outlined;
}

/// One selectable payment method (Figma 18): radio, icon tile, the backend's
/// title and — for cash on delivery and a free order — a line on how it works.
class PaymentMethodTile extends StatelessWidget {
  const PaymentMethodTile({
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
    final subtitle = method.isFree
        ? l10n.checkoutFreeOrder
        : method.isCashOnDelivery
        ? l10n.checkoutCodSubtitle
        : null;
    return CheckoutOption(
      selected: selected,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: 14,
      selectedFill: Colors.white,
      child: Row(
        children: [
          CheckoutRadio(selected: selected),
          const SizedBox(width: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              paymentMethodIcon(method),
              size: 20,
              color: AppColors.inkHeading,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(method.title, style: CheckoutText.bodyStrong),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle, style: CheckoutText.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
