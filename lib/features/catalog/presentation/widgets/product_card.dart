import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/star_glyph.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/widgets/added_to_cart_sheet.dart';
import '../../../wishlist/presentation/widgets/wishlist_heart.dart';
import '../../domain/product.dart';
import 'price_view.dart';

/// Product card per Figma v3 ("Product card", node 6:188): no frame and no
/// shadow, a square image with radius 12 carrying the badges (top-start) and a
/// 36 px white wishlist circle (top-end), then 10 px below it the seller, the
/// name on one line, the star rating and, on the price row, the stacked price
/// and the 36 px navy "+" button.
///
/// The seller line shows when the listing said who sells the product
/// ([Product.sellerKnown]: `hm_seller`, asked only while the server lists
/// HubAppVendors, or an Algolia record's `seller`). Like the website's card,
/// it stays in place but empty for Hub Market's own products, and the rating
/// row keeps its height for a product nobody reviewed yet, so the cards of a
/// row stay level. Nothing is made up: no seller, rating or badge is drawn
/// unless the catalogue said so.
///
/// The card sizes itself from its width (image = width, then
/// [ProductCardMetrics.infoHeight]); grids and rails take their cell height
/// from [ProductCardMetrics.heightFor] / [ProductGridDelegate].
class ProductCard extends ConsumerStatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
    this.onAddedToCart,
    this.dealBadge = false,
    this.rank,
  });

  final Product product;
  final VoidCallback? onTap;

  /// Called after the product is successfully added to the cart (e.g. the
  /// wishlist removes the item on add).
  final VoidCallback? onAddedToCart;

  /// Shows a navy `DEAL` tag above the merchandising/discount badges — used
  /// by the home "Deals of the Day" grid.
  final bool dealBadge;

  /// A best-seller rank (1-based): "#1 Best seller" in gold, "#N" in navy,
  /// in place of the merchandising and discount badges.
  final int? rank;

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  bool _adding = false;

  Product get product => widget.product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rank = widget.rank;
    final discount = rank == null ? product.discountPercent : null;
    final badgeLabel = rank == null ? _badgeLabel(l10n) : null;

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Square image; if the cell is a little short it shrinks, never
            // overflows.
            Flexible(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ColoredBox(color: AppColors.surfaceSubtle),
                      HubImage(url: product.imageUrl),
                      // Merchandising badge over the discount badge (top-start).
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (rank != null)
                              _Badge(
                                label: rank == 1
                                    ? l10n.homeBestSellerFirst
                                    : l10n.homeBestSellerRank(rank),
                                color: rank == 1
                                    ? AppColors.accentGold
                                    : AppColors.brandPrimary,
                                textColor: rank == 1
                                    ? AppColors.inkHeading
                                    : Colors.white,
                              ),
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
                                textColor:
                                    product.badge == ProductBadge.bestseller
                                    ? AppColors.inkHeading
                                    : Colors.white,
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
                      // Wishlist: a 36 px white circle with an 18 px heart, in a
                      // 44 px tap area.
                      PositionedDirectional(
                        top: 4,
                        // Figma: the disc is 4 px from the edge in EN, 8 in AR.
                        end: Directionality.of(context) == TextDirection.rtl
                            ? 4
                            : 0,
                        child: WishlistHeart(sku: product.sku, compact: true),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: ProductCardMetrics.imageGap),
            _Info(product: product, adding: _adding, onAdd: _add),
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
  /// A product that needs choices first — a configurable's size or colour,
  /// a bundle's selections ([Product.requiresOptions]) — can't go in by SKU:
  /// Magento refuses it. Its "+" opens the product page instead, as tapping
  /// the card does, and never calls the cart. When the listing doesn't know
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
}

/// The measurements of the card (Figma 6:188, 171 pt wide: 171 + 10 + 100 =
/// 281 tall), so a grid or a rail can give each cell exactly the height the
/// card needs — for the language's line heights and the user's text size.
abstract final class ProductCardMetrics {
  /// Between the image and the text block.
  static const double imageGap = 10;

  /// Between the rows of the text block.
  static const double rowGap = 4;

  /// The round buttons (wishlist, add).
  static const double buttonSize = 36;

  /// The text block under the image: seller 16, name 20, rating 16 and the
  /// price row 36 (EN, at 1× text), 4 apart — 100.
  static double infoHeight(BuildContext context) {
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    final scaler = MediaQuery.textScalerOf(context);
    double line(double enHeight, double arHeight) =>
        scaler.scale(arabic ? arHeight : enHeight);
    final seller = line(16, 18);
    final name = line(20, 22);
    final rating = line(16, 18);
    final price = line(20, 22) + line(16, 18);
    return seller +
        name +
        rating +
        math.max(buttonSize, price) +
        3 * rowGap;
  }

  /// The card's height at [width].
  static double heightFor(BuildContext context, double width) =>
      width + imageGap + infoHeight(context);
}

/// Two product columns as Figma lays them out (16 px between the columns,
/// 18 between the rows, cells as tall as [ProductCard] needs). Use through
/// [productGridDelegate] to pick up the text size and language.
class ProductGridDelegate extends SliverGridDelegate {
  const ProductGridDelegate({
    required this.infoHeight,
    this.crossAxisCount = 2,
    this.crossAxisSpacing = 16,
    this.mainAxisSpacing = 18,
  });

  final double infoHeight;
  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final usable =
        constraints.crossAxisExtent - crossAxisSpacing * (crossAxisCount - 1);
    final width = usable / crossAxisCount;
    final height = width + ProductCardMetrics.imageGap + infoHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: crossAxisCount,
      mainAxisStride: height + mainAxisSpacing,
      crossAxisStride: width + crossAxisSpacing,
      childMainAxisExtent: height,
      childCrossAxisExtent: width,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(ProductGridDelegate oldDelegate) =>
      oldDelegate.infoHeight != infoHeight ||
      oldDelegate.crossAxisCount != crossAxisCount ||
      oldDelegate.crossAxisSpacing != crossAxisSpacing ||
      oldDelegate.mainAxisSpacing != mainAxisSpacing;
}

/// The grid delegate for a screen of product cards.
ProductGridDelegate productGridDelegate(
  BuildContext context, {
  int crossAxisCount = 2,
}) => ProductGridDelegate(
  infoHeight: ProductCardMetrics.infoHeight(context),
  crossAxisCount: crossAxisCount,
);

/// The text block under the image.
class _Info extends StatelessWidget {
  const _Info({
    required this.product,
    required this.adding,
    required this.onAdd,
  });

  final Product product;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The line (empty for Hub Market's own products) only when the listing
        // asked who sells; Build 1 listings leave it out.
        if (product.sellerKnown) ...[
          _SellerLine(name: product.sellerName),
          const SizedBox(height: ProductCardMetrics.rowGap),
        ],
        Text(
          product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.body.copyWith(color: AppColors.inkHeading),
        ),
        const SizedBox(height: ProductCardMetrics.rowGap),
        _RatingLine(stars: product.starRating, count: product.reviewCount),
        const SizedBox(height: ProductCardMetrics.rowGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: PriceView(product: product)),
            const SizedBox(width: 6),
            if (product.inStock)
              _AddToCartButton(busy: adding, onTap: onAdd)
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  l10n.productOutOfStock,
                  style: t.caption.copyWith(color: AppColors.danger),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The seller above the name (Figma v3 card "vendor": 12 semibold, link blue).
/// Plain text, as on the website's card — the card itself opens the product.
/// [name] null keeps the line's height with nothing in it (Hub Market's own
/// products).
class _SellerLine extends StatelessWidget {
  const _SellerLine({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final style = t.captionStrong.copyWith(color: AppColors.info);
    final seller = name;
    if (seller == null) {
      return SizedBox(height: style.fontSize! * style.height!);
    }
    return Semantics(
      label: AppLocalizations.of(context).productCardSoldBy(seller),
      excludeSemantics: true,
      child: Text(
        seller,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

/// "★ 4.5 (12)" under the name (Figma v3 card): the average of the approved
/// reviews and, when the source says, how many there are. With no rating the
/// row stays as an empty line, so the cards of a row line up.
class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.stars, this.count});

  /// 0–5; null when the product has no reviews.
  final double? stars;

  /// Null (or 0) when the source doesn't say — Algolia records.
  final int? count;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final average = stars;
    if (average == null) {
      return SizedBox(height: t.caption.fontSize! * t.caption.height!);
    }
    final reviews = count ?? 0;
    final value = average.toStringAsFixed(1);
    return Semantics(
      label: AppLocalizations.of(context).productCardRating(value, reviews),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StarGlyph(),
          const SizedBox(width: ProductCardMetrics.rowGap),
          Text(
            value,
            textDirection: TextDirection.ltr,
            style: t.captionStrong.copyWith(color: AppColors.inkHeading),
          ),
          if (reviews > 0) ...[
            const SizedBox(width: ProductCardMetrics.rowGap),
            Text(
              '($reviews)',
              textDirection: TextDirection.ltr,
              style: t.caption.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The navy 36 px "+" in the card's price row (Figma "add"). Shows a spinner
/// while the add is in flight.
class _AddToCartButton extends StatelessWidget {
  const _AddToCartButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Tooltip(
      message: l10n.productAddToCart,
      child: Material(
        color: AppColors.brandPrimary,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: SizedBox(
            width: ProductCardMetrics.buttonSize,
            height: ProductCardMetrics.buttonSize,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(HubIcons.plus, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

/// A badge on the image (Figma "badge": radius 6, 7 × 3 padding, 11 Bold).
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    this.textColor = Colors.white,
  });
  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      // "-15%" must not turn into "15%-" inside a right-to-left paragraph.
      textDirection: TextDirection.ltr,
      style: AppTextStyles.of(context).micro.copyWith(color: textColor),
    ),
  );
}
