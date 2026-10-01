import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/config/free_shipping.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../../catalog/domain/product.dart';
import '../../../catalog/domain/product_detail.dart';
import '../../../catalog/domain/product_preview.dart';
import '../../../catalog/presentation/low_stock_text.dart';
import '../cart_controller.dart';

/// What was just added, as the sheet shows it.
class AddedItem {
  const AddedItem({
    required this.name,
    required this.quantity,
    this.imageUrl,
    this.unitPrice,
    this.options = const <String>[],
    this.onlyLeft,
    this.onlyLeftOption,
  });

  /// From the product page: the chosen variant's image and price, and the
  /// chosen options as "Size: M", like the cart lines — and how many of that
  /// variant are left, when the store says.
  factory AddedItem.fromDetail(
    ProductDetail product,
    Map<String, int> selection,
    int quantity,
  ) {
    final variant = product.variantFor(selection);
    return AddedItem(
      name: product.name,
      quantity: quantity,
      imageUrl:
          variant?.imageUrl ??
          (product.gallery.isEmpty ? null : product.gallery.first),
      unitPrice: variant?.price ?? product.finalPrice ?? product.regularPrice,
      options: [
        for (final option in product.options)
          for (final value in option.values)
            if (value.valueIndex == selection[option.attributeCode])
              '${option.label}: ${value.label}',
      ],
      onlyLeft: product.onlyLeftFor(selection),
      onlyLeftOption: product.stockOptionLabel(selection),
    );
  }

  /// From a listing card, which adds one of a simple product.
  factory AddedItem.fromProduct(Product product) => AddedItem(
    name: product.name,
    quantity: 1,
    imageUrl: product.thumbnail,
    unitPrice: product.finalPrice ?? product.regularPrice,
  );

  final String name;
  final int quantity;
  final String? imageUrl;
  final Money? unitPrice;
  final List<String> options;

  /// Units left of what was added (`only_x_left_in_stock`), with the option
  /// they are of ("size M"): the sheet's "Only 3 left in size M". Null when the
  /// store doesn't say.
  final int? onlyLeft;
  final String? onlyLeftOption;

  /// What this add put in the cart.
  Money? get amount => unitPrice == null
      ? null
      : Money(
          amount: unitPrice!.amount * quantity,
          currency: unitPrice!.currency,
        );
}

/// 14c "Added to cart": what was added, the cart's new subtotal, View cart /
/// Checkout, and — when the product links any — "You might also like".
///
/// Everything comes from data already in hand: the product, the quantity and
/// the cart state the add returned. The free-shipping bar follows the store's
/// threshold and hides without one (Hub Market publishes none yet); the
/// recommendations are the product's own related + upsell links and hide when
/// there are none, as from a listing card.
class AddedToCartSheet extends ConsumerWidget {
  const AddedToCartSheet({
    super.key,
    required this.item,
    this.recommendations = const <Product>[],
  });

  final AddedItem item;
  final List<Product> recommendations;

  static Future<void> show(
    BuildContext context, {
    required AddedItem item,
    List<Product> recommendations = const <Product>[],
  }) => showHubBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    barrierColor: AppColors.brandPrimary.withValues(alpha: 0.45),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) =>
        AddedToCartSheet(item: item, recommendations: recommendations),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final cart = ref.watch(cartControllerProvider.select((s) => s.cart));
    final threshold = ref.watch(freeShippingThresholdProvider).valueOrNull;
    final subtotal = cart.totals.subtotal;
    final router = GoRouter.maybeOf(context);
    // The frame leaves 28 px under the buttons (the home-indicator zone); the
    // sheet's wrapper already lifts the content by the device's own inset.
    final inset = MediaQueryData.fromView(View.of(context)).padding.bottom;

    // Close the sheet, then go on from the page underneath it.
    void leaveTo(String location, {Object? extra}) {
      Navigator.of(context).pop();
      router?.push(location, extra: extra);
    }

    final blocks = <Widget>[
      // Figma "Bottom sheet" handle: 40 × 4, `border/strong`.
      Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.borderStrong,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
      Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.successStrong,
              shape: BoxShape.circle,
            ),
            child: const Icon(HubIcons.check, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.cartAdded,
              style: t.heading2.copyWith(color: AppColors.inkHeading),
            ),
          ),
          HubIconButton(
            icon: HubIcons.x,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      _AddedItemCard(item: item),
      if (threshold != null && subtotal != null)
        _FreeShippingProgress(subtotal: subtotal, threshold: threshold),
      Row(
        children: [
          Expanded(
            child: Text(
              l10n.cartSubtotalItems(cart.itemCount),
              style: t.body.copyWith(color: AppColors.inkSubtle),
            ),
          ),
          Text(
            subtotal?.formatted() ?? '—',
            textDirection: TextDirection.ltr,
            style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => leaveTo(AppRoutes.cart),
              child: Text(l10n.cartViewCart),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              onPressed: () => leaveTo(AppRoutes.checkout),
              child: Text(l10n.cartCheckout),
            ),
          ),
        ],
      ),
      if (recommendations.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.cartAlsoLike,
              style: t.title.copyWith(color: AppColors.inkHeading),
            ),
            const SizedBox(height: 10),
            // A plain scrolling row rather than a fixed-height list: the
            // tiles take the height their text needs (taller in Arabic, or at
            // a large text scale). At most eight — ProductDetail.alsoLike.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < recommendations.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    _MiniCard(
                      product: recommendations[i],
                      onTap: () => leaveTo(
                        AppRoutes.product(recommendations[i].urlKey),
                        extra: ProductPreview.of(recommendations[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
    ];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, (28 - inset).clamp(0, 28)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < blocks.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            blocks[i],
          ],
        ],
      ),
    );
  }
}

/// The added product (Figma "item"): its 64 px photo, the name, the options and
/// quantity, "Only 3 left in size M" in red when the store says so, and what the
/// add put in the cart.
class _AddedItemCard extends StatelessWidget {
  const _AddedItemCard({required this.item});

  final AddedItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final amount = item.amount;
    final left = item.onlyLeft;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          HubImage(
            url: item.imageUrl,
            width: 64,
            height: 64,
            borderRadius: BorderRadius.circular(10),
            error: (_) => const ColoredBox(color: Colors.white),
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
                  style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                ),
                const SizedBox(height: 2),
                Text(
                  [...item.options, l10n.itemQty(item.quantity)].join(' · '),
                  style: t.caption.copyWith(color: AppColors.inkMuted),
                ),
                if (left != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    lowStockText(l10n, left, item.onlyLeftOption),
                    style: t.captionStrong.copyWith(color: AppColors.danger),
                  ),
                ],
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: 12),
            Text(
              amount.formatted(),
              textDirection: TextDirection.ltr,
              style: t.price.copyWith(color: AppColors.inkHeading),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Add AED 7 more for free shipping" with its bar — or, past the threshold,
/// the unlocked line with a full bar (Figma "free-shipping").
class _FreeShippingProgress extends StatelessWidget {
  const _FreeShippingProgress({
    required this.subtotal,
    required this.threshold,
  });

  final Money subtotal;

  /// The store's free-shipping minimum, in the store currency.
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final unlocked = subtotal.amount >= threshold;
    final remaining = Money(
      amount: (threshold - subtotal.amount).clamp(0.0, threshold),
      currency: subtotal.currency,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              HubIcons.truck,
              size: 16,
              color: AppColors.successStrong,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                unlocked
                    ? l10n.cartFreeDeliveryUnlocked
                    : l10n.cartFreeDeliveryRemaining(remaining.formatted()),
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: threshold <= 0
                ? 1
                : (subtotal.amount / threshold).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.surfaceSubtle,
            valueColor: const AlwaysStoppedAnimation(AppColors.successStrong),
          ),
        ),
      ],
    );
  }
}

/// A "You might also like" tile (Figma "mini-card"): a 104 px photo with radius
/// 12, the name in Caption over two lines, and the price in Caption Strong.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final price = product.finalPrice ?? product.regularPrice;
    return SizedBox(
      width: 104,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HubImage(
              url: product.thumbnail,
              width: 104,
              height: 104,
              borderRadius: BorderRadius.circular(12),
              error: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
            ),
            const SizedBox(height: 4),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.caption.copyWith(color: AppColors.inkHeading),
            ),
            if (price != null) ...[
              const SizedBox(height: 4),
              Text(
                price.formatted(),
                textDirection: TextDirection.ltr,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
