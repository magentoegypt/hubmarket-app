import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/free_shipping.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/summary_row.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/cart.dart';
import '../cart_controller.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final TextEditingController _coupon = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Real-time sync: refetch the (customer) cart on tab entry so an add/remove
    // done on the website (same account) shows without a relogin.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(cartControllerProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  CartController get _controller => ref.read(cartControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(cartControllerProvider);

    return HubScaffold(
      currentTab: AppTab.cart,
      showSearch: false,
      // Decluttered header per Figma: back chevron + centered logo, no
      // search/notification icons.
      appBar: AppBar(
        toolbarHeight: 60,
        centerTitle: false,
        titleSpacing: 4,
        leading: HubBackButton(
          onPressed: () =>
              context.canPop() ? context.pop() : context.go(AppRoutes.home),
        ),
        title: const BrandLogo(height: 44),
      ),
      body: _body(l10n, state),
    );
  }

  Widget _body(AppLocalizations l10n, CartState state) {
    if (state.isLoading && state.cart.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.cart.isEmpty) {
      final error = state.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is Failure
                    ? failureMessage(context, error)
                    : l10n.errorGeneric,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _controller.refresh,
                child: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    }
    if (state.cart.isEmpty) {
      // Empty state (Figma "Cart — Empty"): blush cart pill, copy, full-width
      // "Start Shopping", then the marketing footer pinned to the bottom.
      // SliverFillRemaining fills short content and scrolls when it overflows.
      return CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 104,
                            height: 56,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceTint,
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: const Icon(
                              Icons.shopping_cart_outlined,
                              size: 30,
                              color: AppColors.brandPrimary,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            l10n.cartEmptyTitle,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.cartEmptyBody,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.inkMuted),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => context.go(AppRoutes.home),
                              child: Text(l10n.cartStartShopping),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final cart = state.cart;
    final itemCount = cart.items.fold<int>(0, (sum, i) => sum + i.quantity);
    // Free-shipping threshold comes from the backend (Magento's Free Shipping
    // "Minimum Order Amount") — never hardcoded. Null while loading or when the
    // store doesn't publish one (Hub Market doesn't yet), in which case the
    // banner/summary hide the free-shipping story and the delivery line falls
    // back to "at checkout".
    final freeShipThreshold = ref
        .watch(freeShippingThresholdProvider)
        .valueOrNull;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cartHeading,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                l10n.cartItemCount(itemCount),
                style: const TextStyle(color: AppColors.inkMuted),
              ),
            ],
          ),
        ),
        if (cart.totals.subtotal != null && freeShipThreshold != null)
          _FreeDeliveryBanner(
            subtotal: cart.totals.subtotal!,
            threshold: freeShipThreshold,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final item in cart.items)
                _CartItemTile(
                  item: item,
                  busy: state.isMutating,
                  onChangeQty: (q) => _controller.setQuantity(item.uid, q),
                  onRemove: () => _controller.removeItem(item.uid),
                ),
            ],
          ),
        ),
        // Thick grey band (Figma 39:2) — brackets the promo section.
        const _SectionBand(),
        _CouponSection(
          controller: _coupon,
          appliedCoupon: cart.totals.appliedCoupon,
          discount: cart.totals.discount,
          busy: state.isMutating,
          onApply: () async {
            if (_coupon.text.trim().isEmpty) return;
            try {
              await _controller.applyCoupon(_coupon.text.trim());
              _coupon.clear();
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(l10n.cartCouponError)));
              }
            }
          },
          onRemoveCoupon: _controller.removeCoupon,
        ),
        // Thick grey band (Figma 39:26) — closes the promo section.
        const _SectionBand(),
        // Order Summary (Figma 39:27).
        _OrderSummary(cart: cart, freeDeliveryThreshold: freeShipThreshold),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => context.push(AppRoutes.checkout),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      cart.totals.grandTotal != null
                          ? '${l10n.cartSecureCheckout} · ${cart.totals.grandTotal!.formatted()}'
                          : l10n.cartSecureCheckout,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.busy,
    required this.onChangeQty,
    required this.onRemove,
  });

  final CartItem item;
  final bool busy;
  final ValueChanged<int> onChangeQty;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HubImage(
            url: item.imageUrl,
            width: 72,
            height: 72,
            borderRadius: BorderRadius.circular(8),
            error: (_) => const ColoredBox(color: AppColors.surfaceTint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                for (final option in item.options)
                  Text(
                    option,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 6),
                if (item.unitPrice != null)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.unitPrice!.formatted(),
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.brandPrimary,
                        ),
                      ),
                      if (item.isDiscounted) ...[
                        const SizedBox(width: 8),
                        Text(
                          item.originalUnitPrice!.formatted(),
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _QtyButton(
                      icon: Icons.remove,
                      onTap: busy ? null : () => onChangeQty(item.quantity - 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('${item.quantity}'),
                    ),
                    _QtyButton(
                      icon: Icons.add,
                      onTap: busy ? null : () => onChangeQty(item.quantity + 1),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.inkMuted),
            onPressed: busy ? null : onRemove,
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.inkMuted.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: 16),
    ),
  );
}

/// Full-bleed 8px grey band that separates cart sections (Figma 39:2 / 39:26).
class _SectionBand extends StatelessWidget {
  const _SectionBand();

  @override
  Widget build(BuildContext context) =>
      Container(height: 8, color: AppColors.surfaceMuted);
}

/// Copy-to-clipboard affordance at the trailing edge of the promo-code field
/// (CL042-DEV13). Copies whatever code is in play — what the shopper has typed,
/// or the live coupon once one is applied — so a code seen in the announcement
/// bar or on an offer card can be carried out of the app.
///
/// It listens to the field's own [TextEditingController] so it appears the
/// moment there is something to copy, and takes no space when there isn't.
class _CopyCodeButton extends StatelessWidget {
  const _CopyCodeButton({required this.controller, required this.appliedCoupon});

  final TextEditingController controller;
  final String? appliedCoupon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final code = value.text.trim().isNotEmpty
            ? value.text.trim()
            : (appliedCoupon ?? '');
        if (code.isEmpty) return const SizedBox.shrink();
        return InkWell(
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: code));
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.cartCouponCopied)),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            // Keeps the 48px tap target without growing the field's height.
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 0, 4),
            child: Tooltip(
              message: l10n.actionCopy,
              child: const Icon(
                Icons.copy_outlined,
                size: 17,
                color: AppColors.brandPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Promo / gift-code entry (Figma "promo" 39:3): a filled grey field with a
/// tag icon + muted placeholder, a burgundy outlined "Apply" pill, and — when a
/// coupon is live — a blush chip showing the code, the saving, and a remove ×.
class _CouponSection extends StatelessWidget {
  const _CouponSection({
    required this.controller,
    required this.appliedCoupon,
    required this.discount,
    required this.busy,
    required this.onApply,
    required this.onRemoveCoupon,
  });

  final TextEditingController controller;
  final String? appliedCoupon;
  final Money? discount;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onRemoveCoupon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // Filled grey field with a tag icon prefix (Figma 39:5).
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_offer_outlined,
                        size: 17,
                        color: AppColors.inkFaint,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          enabled: !busy,
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.inkHeading,
                          ),
                          decoration: InputDecoration(
                            hintText: l10n.cartCouponHint,
                            hintStyle: const TextStyle(
                              color: AppColors.inkFaint,
                              fontSize: 13,
                            ),
                            isCollapsed: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onSubmitted: (_) => busy ? null : onApply(),
                        ),
                      ),
                      _CopyCodeButton(
                        controller: controller,
                        appliedCoupon: appliedCoupon,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Burgundy outlined "Apply" pill (Figma 39:11).
              OutlinedButton(
                onPressed: busy ? null : onApply,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandPrimary,
                  side: const BorderSide(
                    color: AppColors.brandPrimary,
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 13,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(l10n.cartApply),
              ),
            ],
          ),
          // Applied-coupon chip (Figma 39:13).
          if (appliedCoupon != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.local_offer_outlined,
                    size: 16,
                    color: AppColors.brandPrimary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.cartCouponApplied(appliedCoupon!),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                  ),
                  if (discount != null) ...[
                    Text(
                      '−${discount!.formatted()}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  InkWell(
                    onTap: busy ? null : onRemoveCoupon,
                    borderRadius: BorderRadius.circular(12),
                    child: const Icon(
                      Icons.close,
                      size: 15,
                      color: AppColors.brandPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Order Summary block (Figma 39:27): subtotal, optional promo line, the
/// delivery line (FREE past the threshold, otherwise "calculated at
/// checkout"), a divider, then the total in burgundy.
class _OrderSummary extends StatelessWidget {
  const _OrderSummary({required this.cart, this.freeDeliveryThreshold});

  final Cart cart;

  /// Free-shipping threshold (AED) from store config; null when unconfigured/
  /// still loading, in which case delivery falls back to "calculated at checkout".
  final double? freeDeliveryThreshold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = cart.totals;
    final itemCount = cart.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final subtotal = totals.subtotal;
    final threshold = freeDeliveryThreshold;
    final freeDelivery =
        subtotal != null && threshold != null && subtotal.amount >= threshold;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.cartOrderSummary,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.inkHeading,
            ),
          ),
          const SizedBox(height: 11),
          SummaryRow(
            label: l10n.cartSubtotalCount(itemCount),
            value: subtotal?.formatted(),
          ),
          if (totals.discount != null) ...[
            const SizedBox(height: 11),
            SummaryRow(
              label: totals.appliedCoupon != null
                  ? l10n.cartPromoCode(totals.appliedCoupon!)
                  : l10n.cartDiscount,
              value: '−${totals.discount!.formatted()}',
              valueColor: AppColors.brandPrimary,
            ),
          ],
          // Delivery line always shows: FREE once the threshold is met,
          // otherwise the fee is resolved at checkout (it depends on the
          // emirate, so the cart can't know the amount yet).
          const SizedBox(height: 11),
          SummaryRow(
            label: l10n.cartDelivery,
            value: freeDelivery
                ? l10n.cartDeliveryFree
                : l10n.cartDeliveryCalculated,
            valueColor: freeDelivery ? AppColors.brandPrimary : null,
            valueWeight: freeDelivery ? FontWeight.w700 : FontWeight.w500,
          ),
          const SizedBox(height: 11),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.borderDefault,
          ),
          const SizedBox(height: 11),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.cartTotal,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkHeading,
                ),
              ),
              Text(
                totals.grandTotal?.formatted() ?? '—',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Blush progress banner toward the free 3-hour delivery threshold (Figma).
/// Shows remaining-to-go with a partial bar, or an unlocked state once met.
class _FreeDeliveryBanner extends StatelessWidget {
  const _FreeDeliveryBanner({required this.subtotal, required this.threshold});

  final Money subtotal;

  /// Free-shipping threshold (AED) from store config (never hardcoded).
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final amount = subtotal.amount;
    final unlocked = amount >= threshold;
    final progress = (amount / threshold).clamp(0.0, 1.0);
    final remaining = Money(
      amount: (threshold - amount).clamp(0.0, threshold),
      currency: subtotal.currency,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brandPrimary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                unlocked
                    ? Icons.check_circle
                    : Icons.local_shipping_outlined,
                size: 18,
                color: unlocked ? AppColors.success : AppColors.brandPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unlocked
                      ? l10n.cartFreeDeliveryUnlocked
                      : l10n.cartFreeDeliveryRemaining(remaining.formatted()),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.inkHeading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(
                unlocked ? AppColors.success : AppColors.brandPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
