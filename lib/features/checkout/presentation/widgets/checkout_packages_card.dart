import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/cart.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import 'checkout_parts.dart';

/// How many packages the cart's lines ship in: one per store, from the lines'
/// `hm_seller` (HubApp). Null when no line names a seller (Build 1), where the
/// backend can't say.
int? packageCountOf(Cart cart) =>
    groupBySeller<CartItem>(cart.items, (item) => item.seller)?.length;

/// "Your order ships in 2 packages" (Figma 17 "packages (info)"): each store the
/// order ships from with its logo and name, and thumbnails of its lines at the
/// end. Nothing without HubApp, whose cart lines name no seller.
class CheckoutPackagesCard extends StatelessWidget {
  const CheckoutPackagesCard({super.key, required this.cart});

  final Cart cart;

  /// Thumbnails per package; a store with more lines shows "+N".
  static const int maxThumbnails = 3;

  @override
  Widget build(BuildContext context) {
    final groups = groupBySeller<CartItem>(cart.items, (item) => item.seller);
    if (groups == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final t = CheckoutText.of(context);
    return CheckoutCard(
      spacing: 4,
      children: [
        Row(
          children: [
            const Icon(HubIcons.package, size: 18, color: AppColors.info),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.checkoutShipsInPackages(groups.length),
                style: t.title,
              ),
            ),
          ],
        ),
        for (var i = 0; i < groups.length; i++)
          _PackageRow(index: i + 1, group: groups[i]),
      ],
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.index, required this.group});

  /// 1-based, for a store-less group.
  final int index;
  final SellerGroup<CartItem> group;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = CheckoutText.of(context);
    final seller = group.seller;
    final shown = group.items.take(CheckoutPackagesCard.maxThumbnails).toList();
    final more = group.items.length - shown.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (seller != null)
            SellerLogo(seller: seller, size: 24)
          else
            const SizedBox(
              width: 24,
              child: Icon(
                HubIcons.package,
                size: 18,
                color: AppColors.inkMuted,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              seller?.name ?? l10n.orderPackageTitleNoStore(index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyStrong,
            ),
          ),
          const SizedBox(width: 10),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            HubImage(
              url: shown[i].imageUrl,
              width: 36,
              height: 36,
              borderRadius: BorderRadius.circular(8),
              placeholder: (_) =>
                  const ColoredBox(color: AppColors.surfaceSubtle),
              error: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
            ),
          ],
          if (more > 0) ...[
            const SizedBox(width: 6),
            Text('+$more', textDirection: TextDirection.ltr, style: t.caption),
          ],
        ],
      ),
    );
  }
}
