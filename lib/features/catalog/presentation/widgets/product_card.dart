import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/widgets/added_to_cart_sheet.dart';
import '../../../wishlist/presentation/widgets/wishlist_heart.dart';
import '../../domain/product.dart';
import 'price_view.dart';

/// Product card per Figma: a bordered white card with a full-bleed image
/// carrying NEW/BESTSELLER + discount badges (top-start) and stacked wishlist +
/// share actions (top-end), then a name + stacked-price panel. Image degrades
/// to a neutral placeholder and the merchandising badge only shows when the
/// catalogue actually flags it (no fabricated imagery or badges).
class ProductCard extends ConsumerStatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onAddedToCart,
    this.dealBadge = false,
  });

  final Product product;
  final VoidCallback? onTap;

  /// Called after the product is successfully added to the cart (e.g. the
  /// wishlist removes the item on add).
  final VoidCallback? onAddedToCart;

  /// Shows a navy `DEAL` tag above the merchandising/discount badges — used
  /// by the home "Deals of the Day" grid.
  final bool dealBadge;

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  bool _adding = false;

  Product get product => widget.product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final discount = product.discountPercent;
    final badgeLabel = _badgeLabel(l10n);

    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: widget.onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: HubImage(url: product.imageUrl),
                  ),
                  // Merchandising badge over the discount badge (top-start).
                  PositionedDirectional(
                    top: 8,
                    start: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.dealBadge) ...[
                          _Badge(
                            label: l10n.homeDealBadge,
                            color: AppColors.brandPrimary,
                          ),
                          if (badgeLabel != null || discount != null)
                            const SizedBox(height: 4),
                        ],
                        if (badgeLabel != null)
                          _Badge(
                            label: badgeLabel,
                            color: product.badge == ProductBadge.bestseller
                                ? AppColors.accentGold
                                : AppColors.brandPrimary,
                          ),
                        if (badgeLabel != null && discount != null)
                          const SizedBox(height: 4),
                        if (discount != null)
                          _Badge(
                            label: '-$discount%',
                            color: AppColors.accentSale,
                          ),
                      ],
                    ),
                  ),
                  // Wishlist heart with the share action stacked beneath it.
                  PositionedDirectional(
                    top: 8,
                    end: 8,
                    child: _CircleAction(
                      child: WishlistHeart(sku: product.sku, compact: true),
                    ),
                  ),
                  PositionedDirectional(
                    top: 40,
                    end: 8,
                    child: _CircleAction(
                      child: IconButton(
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 26,
                          height: 26,
                        ),
                        tooltip: l10n.actionShare,
                        icon: const Icon(
                          Icons.ios_share,
                          color: AppColors.inkHeading,
                        ),
                        onPressed: () => _share(l10n),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.inkHeading,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (!product.inStock)
                    Text(
                      l10n.productOutOfStock,
                      style: const TextStyle(
                        color: AppColors.accentSale,
                        fontSize: 12,
                      ),
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(child: PriceView(product: product)),
                        const SizedBox(width: 6),
                        _AddToCartButton(busy: _adding, onTap: _add),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _badgeLabel(AppLocalizations l10n) => switch (product.badge) {
    ProductBadge.isNew => l10n.badgeNew,
    ProductBadge.bestseller => l10n.badgeBestseller,
    ProductBadge.none => null,
  };

  /// Adds the product to the cart by SKU (the cart controller self-heals a
  /// stale/consumed cart) and confirms with the added-to-cart sheet.
  ///
  /// A product that needs choices first — a configurable's size or colour
  /// ([Product.requiresOptions]) — can't go in by SKU, so its "+" opens the
  /// product page, as tapping the card does. When the listing doesn't know
  /// the product's type, the add is attempted and a refusal shows the
  /// generic error.
  Future<void> _add() async {
    if (product.requiresOptions) {
      widget.onTap?.call();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _adding = true);
    try {
      await ref
          .read(cartControllerProvider.notifier)
          .addToCart(sku: product.sku);
      if (!mounted) return;
      // Shown before the callback: the wishlist drops the card on add, and the
      // sheet needs this context to find its navigator.
      AddedToCartSheet.show(context, item: AddedItem.fromProduct(product));
      widget.onAddedToCart?.call();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  /// Shares the product via the OS share sheet, using the active store's
  /// canonical web URL when available (falls back to a name-only message).
  Future<void> _share(AppLocalizations l10n) async {
    final message = l10n.shareProduct(product.name);
    final url = productUrl(ref.read(storeControllerProvider), product.urlKey);
    await SharePlus.instance.share(
      ShareParams(text: url == null ? message : '$message\n$url'),
    );
  }
}

/// Compact navy add-to-cart button in the card footer (Figma / site grid
/// card). Shows a spinner while the add is in flight.
class _AddToCartButton extends StatelessWidget {
  const _AddToCartButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.brandPrimary,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: SizedBox(
          width: 34,
          height: 34,
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Tooltip(
                  message: l10n.productAddToCart,
                  child: const Icon(
                    Icons.add_shopping_cart,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 26,
    height: 26,
    clipBehavior: Clip.antiAlias,
    decoration: const BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(
        BorderSide(color: AppColors.borderDefault),
      ),
    ),
    child: child,
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      ),
    ),
  );
}
