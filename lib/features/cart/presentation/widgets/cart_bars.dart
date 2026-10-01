import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';

/// Figma 16 "free-shipping-bar": a pale orange card with the truck, how much is
/// missing and a 6 px bar. [threshold] is the store's own figure
/// (`hmAppConfig.shipping.free_over`), never a number of the app's: the card
/// only exists where the store publishes one. Once the cart reaches it the card
/// turns green and says so.
class CartFreeShippingBar extends StatelessWidget {
  const CartFreeShippingBar({
    super.key,
    required this.subtotal,
    required this.threshold,
  });

  final Money subtotal;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final amount = subtotal.amount;
    final unlocked = amount >= threshold;
    final progress = (amount / threshold).clamp(0.0, 1.0);
    final remaining = Money(
      amount: (threshold - amount).clamp(0.0, threshold),
      currency: subtotal.currency,
    );
    final ink = unlocked ? AppColors.successStrong : AppColors.accentStrong;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: unlocked ? AppColors.successSubtle : AppColors.accentSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? HubIcons.circleCheck : HubIcons.truck,
                size: 16,
                color: ink,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unlocked
                      ? l10n.cartFreeShippingUnlocked
                      : l10n.cartFreeShippingRemaining(remaining.formatted()),
                  style: t.captionStrong.copyWith(color: ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // A white track under an orange fill, both fully rounded.
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: Colors.white,
            valueColor: AlwaysStoppedAnimation(
              unlocked ? AppColors.success : AppColors.accent,
            ),
            trackGap: 0,
            stopIndicatorRadius: 0,
          ),
        ],
      ),
    );
  }
}

/// Figma 16 "checkout-bar": pinned above the tab bar, the order total on the
/// left and the navy Checkout button taking the rest of the row.
class CartCheckoutBar extends StatelessWidget {
  const CartCheckoutBar({
    super.key,
    required this.total,
    required this.onCheckout,
  });

  final Money? total;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // A Container, so the hairline on top adds its own pixel (1 + 12 + 52 + 12).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cartTotal,
                style: t.caption.copyWith(color: AppColors.inkMuted),
              ),
              Text(
                total?.formatted() ?? '—',
                textDirection: TextDirection.ltr,
                style: t.priceLarge.copyWith(color: AppColors.inkHeading),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: FilledButton(
              onPressed: onCheckout,
              child: Text(l10n.cartCheckout),
            ),
          ),
        ],
      ),
    );
  }
}

/// The checkout bar's stand-in while the cart is in selection mode: "Select all"
/// at the start and a "Remove (n)" button taking the rest of the row.
class CartSelectionBar extends StatelessWidget {
  const CartSelectionBar({
    super.key,
    required this.count,
    required this.allSelected,
    required this.onToggleAll,
    required this.onRemove,
  });

  /// How many lines are ticked.
  final int count;
  final bool allSelected;
  final VoidCallback onToggleAll;

  /// Null-ish while nothing is ticked: the button is then off.
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // A Container, so the hairline on top adds its own pixel (1 + 12 + 52 + 12).
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onToggleAll,
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 52,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: 1,
                child: Text(
                  allSelected ? l10n.cartSelectNone : l10n.cartSelectAll,
                  style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: HubButton(
              label: l10n.cartRemoveSelected(count),
              icon: HubIcons.trash2,
              style: HubButtonStyle.danger,
              onPressed: count == 0 ? null : onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
