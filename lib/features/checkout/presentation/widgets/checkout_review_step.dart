import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/cart.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/checkout.dart';
import 'checkout_parts.dart';
import 'payment_method_tile.dart';

/// Step 3 cards (Figma 18b): what ships where and how, how it is paid, and
/// the items.

/// "Shipping" — the address and the chosen method, with "Edit" back to step 1.
class ReviewShippingCard extends StatelessWidget {
  const ReviewShippingCard({
    super.key,
    required this.shipTo,
    required this.method,
    required this.onEdit,
  });

  final ShipTo? shipTo;
  final ShippingMethodOption? method;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final to = shipTo;
    final m = method;
    return CheckoutCard(
      title: l10n.checkoutStepShipping,
      trailing: CheckoutLink(
        label: l10n.actionEdit,
        icon: Icons.edit_outlined,
        onTap: onEdit,
      ),
      children: [
        if (to != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppColors.accentStrong,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${to.name} · ${displayPhone(to.telephone)}',
                      style: CheckoutText.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(to.address, style: CheckoutText.caption),
                  ],
                ),
              ),
            ],
          ),
        if (m != null)
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 18,
                color: AppColors.inkHeading,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(m.label, style: CheckoutText.body)),
              const SizedBox(width: 12),
              m.isFree
                  ? Text(
                      l10n.cartDeliveryFree,
                      style: CheckoutText.bodyStrong.copyWith(
                        color: AppColors.successStrong,
                      ),
                    )
                  : MoneyText(m.amount),
            ],
          ),
      ],
    );
  }
}

/// "Payment" — the chosen method, with "Edit" back to step 2.
class ReviewPaymentCard extends StatelessWidget {
  const ReviewPaymentCard({
    super.key,
    required this.method,
    required this.onEdit,
  });

  final PaymentMethodOption method;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CheckoutCard(
      title: l10n.checkoutStepPayment,
      trailing: CheckoutLink(
        label: l10n.actionEdit,
        icon: Icons.edit_outlined,
        onTap: onEdit,
      ),
      children: [
        Row(
          children: [
            Icon(
              paymentMethodIcon(method),
              size: 20,
              color: AppColors.inkHeading,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(method.title, style: CheckoutText.body)),
          ],
        ),
      ],
    );
  }
}

/// "Items (N)" — every cart line: thumbnail, name, options and quantity, and
/// the line total.
class ReviewItemsCard extends StatelessWidget {
  const ReviewItemsCard({super.key, required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CheckoutCard(
      title: l10n.checkoutItemsCount(cart.itemCount),
      spacing: 2,
      children: [for (final item in cart.items) ReviewItemRow(item: item)],
    );
  }
}

class ReviewItemRow extends StatelessWidget {
  const ReviewItemRow({super.key, required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = item.unitPrice;
    final lineTotal =
        item.rowTotal ??
        (unit == null
            ? null
            : Money(
                amount: unit.amount * item.quantity,
                currency: unit.currency,
              ));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          HubImage(
            url: item.imageUrl,
            width: 44,
            height: 44,
            borderRadius: BorderRadius.circular(8),
            error: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CheckoutText.bodyStrong,
                ),
                Text(
                  [...item.options, l10n.itemQty(item.quantity)].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: CheckoutText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          MoneyText(lineTotal),
        ],
      ),
    );
  }
}
