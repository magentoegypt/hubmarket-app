import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../../home/presentation/home_providers.dart';
import '../../domain/cart.dart';

/// What the lines saved against their regular prices: the sum of (regular −
/// charged) × quantity over the discounted lines — Figma 16's "You save". Null
/// when nothing is discounted. Coupons are their own line, not part of it.
Money? cartSavings(Cart cart) {
  var amount = 0.0;
  String? currency;
  for (final item in cart.items) {
    if (!item.isDiscounted) continue;
    amount +=
        (item.originalUnitPrice!.amount - item.unitPrice!.amount) *
        item.quantity;
    currency ??= item.unitPrice!.currency;
  }
  if (currency == null || amount <= 0.004) return null;
  return Money(amount: amount, currency: currency);
}

/// The cart's summary card (Figma 16 "summary"): the subtotal, what the lines
/// saved, a coupon, the shipping estimate, store credit, then the total. Every
/// line the cart has no figure for is left out.
class CartSummaryCard extends StatelessWidget {
  const CartSummaryCard({
    super.key,
    required this.cart,
    this.freeShippingThreshold,
    this.storeCredit,
  });

  final Cart cart;

  /// The store's free-shipping threshold (AED); null when it publishes none or
  /// it is still loading, so the shipping line falls back to "calculated at
  /// checkout".
  final double? freeShippingThreshold;

  /// Store credit used on the cart (HubApp), already off the total below; null
  /// — no line — in Build 1 and when none is applied.
  final Money? storeCredit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final totals = cart.totals;
    final itemCount = cart.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final subtotal = totals.subtotal;
    final threshold = freeShippingThreshold;
    final shipping = totals.shipping;
    final freeShipping = shipping != null
        ? shipping.amount <= 0.0001
        : subtotal != null && threshold != null && subtotal.amount >= threshold;
    final savings = cartSavings(cart);
    // Once a shipping method was chosen at checkout its fee is shown (the total
    // includes it); before that, FREE past the threshold, else "calculated at
    // checkout" — the fee depends on the emirate.
    final shippingValue = freeShipping
        ? l10n.cartDeliveryFree
        : shipping?.formatted() ?? l10n.cartDeliveryCalculated;

    Widget row(String label, String value, {Color? color}) => Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: t.body.copyWith(color: AppColors.inkSubtle),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: t.bodyStrong.copyWith(color: color ?? AppColors.inkHeading),
        ),
      ],
    );

    final rows = <Widget>[
      row(l10n.cartSubtotalCount(itemCount), subtotal?.formatted() ?? '—'),
      if (savings != null)
        row(
          l10n.cartYouSave,
          '− ${savings.formatted()}',
          color: AppColors.successStrong,
        ),
      if (totals.discount != null)
        row(
          totals.appliedCoupon != null
              ? l10n.cartPromoCode(totals.appliedCoupon!)
              : l10n.cartDiscount,
          '− ${totals.discount!.formatted()}',
          color: AppColors.successStrong,
        ),
      row(
        l10n.cartShippingEstimated,
        shippingValue,
        color: freeShipping ? AppColors.successStrong : null,
      ),
      // Credit used at checkout is already off the total below.
      if (storeCredit != null)
        row(
          l10n.checkoutStoreCredit,
          '− ${storeCredit!.formatted()}',
          color: AppColors.successStrong,
        ),
      const Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
      Row(
        children: [
          Expanded(
            child: Text(
              l10n.checkoutTotalInclVat,
              style: t.title.copyWith(color: AppColors.inkHeading),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            totals.grandTotal?.formatted() ?? '—',
            textDirection: TextDirection.ltr,
            style: t.price.copyWith(color: AppColors.inkHeading),
          ),
        ],
      ),
    ];
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Figma 16 "cart-trust": green ticks under the summary. They are the
/// storefront's own trust items (the CMS block `hm_home_trust` that the Home and
/// the product page show), so marketing edits them once and the cart promises
/// only what the store says; hidden when the block is empty or unreadable.
class CartTrustTicks extends ConsumerWidget {
  const CartTrustTicks({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(homeTrustProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    final t = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  HubIcons.check,
                  size: 14,
                  color: AppColors.successStrong,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[i].text.isEmpty
                        ? items[i].title
                        : '${items[i].title} · ${items[i].text}',
                    style: t.caption.copyWith(color: AppColors.inkSubtle),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
