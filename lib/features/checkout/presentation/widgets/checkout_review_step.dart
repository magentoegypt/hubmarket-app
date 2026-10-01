import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/cart.dart';
import '../../../catalog/domain/money.dart';
import '../../../cms/presentation/widgets/legal_links_text.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
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
    final t = CheckoutText.of(context);
    final to = shipTo;
    final m = method;
    return CheckoutCard(
      title: l10n.checkoutStepShipping,
      trailing: CheckoutLink(
        label: l10n.actionEdit,
        icon: HubIcons.pencil,
        onTap: onEdit,
      ),
      children: [
        if (to != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                HubIcons.mapPin,
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
                      style: t.bodyStrong,
                    ),
                    const SizedBox(height: 2),
                    Text(to.address, style: t.caption),
                  ],
                ),
              ),
            ],
          ),
        if (m != null)
          Row(
            children: [
              const Icon(HubIcons.truck, size: 18, color: AppColors.inkSubtle),
              const SizedBox(width: 10),
              Expanded(child: Text(m.label, style: t.body)),
              const SizedBox(width: 10),
              m.isFree
                  ? Text(
                      l10n.cartDeliveryFree,
                      style: t.bodyStrong.copyWith(
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
    final t = CheckoutText.of(context);
    return CheckoutCard(
      title: l10n.checkoutStepPayment,
      trailing: CheckoutLink(
        label: l10n.actionEdit,
        icon: HubIcons.pencil,
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
            Expanded(child: Text(method.title, style: t.body)),
          ],
        ),
      ],
    );
  }
}

/// The terms line under the totals: "By placing your order you agree to Hub
/// Market's Terms …", "Terms" opening the store's terms page (the website
/// footer's link, see [LegalLinksText]).
class ReviewTermsNote extends StatelessWidget {
  const ReviewTermsNote({super.key});

  @override
  Widget build(BuildContext context) => LegalLinksText(
    AppLocalizations.of(context).checkoutTermsNote,
    style: CheckoutText.of(context).caption,
  );
}

/// "Items (N)" — every cart line: thumbnail, name, quantity and options, and
/// the line total. With HubApp the lines come grouped by store, each under
/// the store's name, a hairline between stores (Figma 18b).
class ReviewItemsCard extends StatelessWidget {
  const ReviewItemsCard({super.key, required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final groups = groupBySeller<CartItem>(cart.items, (item) => item.seller);
    // The store's line and its items, 2 px apart (Figma "col").
    Widget column(List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          rows[i],
        ],
      ],
    );
    Widget block(SellerGroup<CartItem> group) => column([
      if (group.seller case final seller?) _StoreCaption(seller: seller),
      for (final item in group.items) ReviewItemRow(item: item),
    ]);
    return CheckoutCard(
      title: l10n.checkoutItemsCount(cart.itemCount),
      children: [
        if (groups == null)
          column([for (final item in cart.items) ReviewItemRow(item: item)])
        else
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.borderSubtle,
              ),
            block(groups[i]),
          ],
      ],
    );
  }
}

/// The store line above its items (Figma 18b): a 22 px logo and the name in
/// Caption Strong, `--hm-subtle`.
class _StoreCaption extends StatelessWidget {
  const _StoreCaption({required this.seller});

  final HmSellerSummary seller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SellerLogo(seller: seller, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            seller.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: CheckoutText.of(
              context,
            ).captionStrong.copyWith(color: AppColors.inkSubtle),
          ),
        ),
      ],
    ),
  );
}

class ReviewItemRow extends StatelessWidget {
  const ReviewItemRow({super.key, required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = CheckoutText.of(context);
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
            placeholder: (_) =>
                const ColoredBox(color: AppColors.surfaceSubtle),
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
                  style: t.bodyStrong,
                ),
                // The chosen options and the quantity: "Colour: Teal · Qty 1"
                // (the frame's "Qty 1" for a line without options).
                Text(
                  [...item.options, l10n.itemQty(item.quantity)].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption,
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
