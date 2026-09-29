import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/marketing_footer.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/free_shipping.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../checkout/payments/tabby_promo.dart';
import '../../../wishlist/presentation/widgets/wishlist_heart.dart';
import '../../domain/money.dart';
import '../../domain/product.dart';
import '../../domain/product_detail.dart';
import '../../domain/product_preview.dart';
import '../catalog_providers.dart';
import '../product_navigation.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.urlKey, this.preview});

  final String urlKey;

  /// What the listing already knew, when we arrived from one. Used solely to
  /// paint a real loading state; never a substitute for the loaded document.
  final ProductPreview? preview;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  final Map<String, int> _selection = <String, int>{};
  final ScrollController _scroll = ScrollController();
  int _tab = 0;
  int _quantity = 1;
  bool _showBar = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  /// Retract the sticky Add-to-Cart bar as the marketing footer scrolls into
  /// view so it never overlaps it (QA #3). Self-stabilising: hiding the bar
  /// grows the viewport (shrinking `remaining`), which keeps it hidden; showing
  /// it does the reverse — so there's no oscillation at the boundary.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final show = pos.maxScrollExtent - pos.pixels > 300;
    if (show != _showBar) setState(() => _showBar = show);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detail = ref.watch(productDetailProvider(widget.urlKey));

    return HubScaffold(
      currentTab: AppTab.home,
      // Sticky Add-to-Cart bar (Figma) pinned above the bottom nav — shown once
      // the product has loaded, and retracted as the footer scrolls into view.
      bottomBar: detail.maybeWhen(
        data: (product) => (product == null || !_showBar)
            ? null
            : _StickyAddToCart(
                product: product,
                selection: _selection,
                quantity: _quantity,
              ),
        orElse: () => null,
      ),
      body: AsyncValueView(
        value: detail,
        loading: () => ProductDetailSkeleton(preview: widget.preview),
        onRetry: () => ref.invalidate(productDetailProvider(widget.urlKey)),
        data: (product) {
          if (product == null) {
            // A stale or rewritten link lands here — give it a way out
            // rather than a bare string in the middle of the page.
            return EmptyState(
              icon: Icons.link_off,
              title: l10n.linkNotFoundTitle,
              body: l10n.linkNotFoundBody,
              action: FilledButton(
                onPressed: () => context.go(AppRoutes.home),
                child: Text(l10n.navHome),
              ),
            );
          }
          return _Content(
            product: product,
            scrollController: _scroll,
            selection: _selection,
            tab: _tab,
            quantity: _quantity,
            onSelect: (code, value) => setState(() => _selection[code] = value),
            onTab: (index) => setState(() => _tab = index),
            onQuantity: (value) => setState(() => _quantity = value),
          );
        },
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.product,
    required this.scrollController,
    required this.selection,
    required this.tab,
    required this.quantity,
    required this.onSelect,
    required this.onTab,
    required this.onQuantity,
  });

  final ProductDetail product;
  final ScrollController scrollController;
  final Map<String, int> selection;
  final int tab;
  final int quantity;
  final void Function(String code, int value) onSelect;
  final ValueChanged<int> onTab;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final variant = product.variantFor(selection);
    final price = variant?.price ?? product.finalPrice ?? product.regularPrice;
    final images = <String>[
      if (variant?.imageUrl != null) variant!.imageUrl!,
      ...product.gallery,
    ];

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        _Gallery(
          images: images,
          sku: product.sku,
          urlKey: product.urlKey,
          badge: product.badge,
          discountPercent: product.discountPercent,
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (product.brand != null && product.brand!.isNotEmpty)
                Text(
                  product.brand!,
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              Text(
                product.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              // Rating line under the title (Figma) — only when real reviews
              // exist; never fabricate stars.
              if (product.hasReviews) ...[
                const SizedBox(height: 6),
                _RatingLine(
                  ratingSummary: product.ratingSummary,
                  reviewCount: product.reviewCount,
                ),
              ],
              const SizedBox(height: 12),
              _PriceRow(
                price: price,
                product: product,
                showStruck: variant == null,
              ),
              const SizedBox(height: 16),
              for (final option in product.options)
                _OptionSelector(
                  option: option,
                  selectedValue: selection[option.attributeCode],
                  onSelect: (value) => onSelect(option.attributeCode, value),
                ),
              const _SectionDivider(),
              _QuantityStepper(quantity: quantity, onChanged: onQuantity),
              if (price != null) ...[
                const _SectionDivider(),
                TabbyPromo(price: price),
              ],
              const SizedBox(height: 16),
              const _TrustRow(),
              const SizedBox(height: 24),
              _Tabs(current: tab, onTab: onTab),
              const SizedBox(height: 12),
              _TabContent(product: product, tab: tab),
            ],
          ),
        ),
        _RelatedProducts(products: product.alsoLike),
        const MarketingFooter(),
      ],
    );
  }
}

/// "You may also like" horizontal rail (Figma), driven by the product's core
/// Magento related + upsell links ([ProductDetail.alsoLike]). Hidden entirely
/// when the product links nothing (no fabricated recommendations).
class _RelatedProducts extends StatefulWidget {
  const _RelatedProducts({required this.products});
  final List<Product> products;

  @override
  State<_RelatedProducts> createState() => _RelatedProductsState();
}

class _RelatedProductsState extends State<_RelatedProducts> {
  static const double _cardWidth = 150;

  @override
  void initState() {
    super.initState();
    // After the frame, so warming the rail never races the hero image the
    // user is actually looking at. Only the cards in view.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        prefetchImages(
          context,
          widget.products.map((p) => p.imageUrl),
          decodeWidth: HubImage.decodePixels(context, _cardWidth),
          limit: 4,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final related = widget.products;
    if (related.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            l10n.pdpYouMayAlsoLike,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final product = related[i];
              return SizedBox(
                width: _cardWidth,
                child: ProductCard(
                  product: product,
                  onTap: () =>
                      openProduct(context, product),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Hairline section separator used between PDP info blocks (Figma).
class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 12),
    child: Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
  );
}

/// Star + "4.6 · N reviews" line under the product title (Figma).
class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.ratingSummary, required this.reviewCount});

  /// 0–100 (Magento `rating_summary`).
  final int ratingSummary;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rating = ratingSummary / 20; // 0–5
    final filled = rating.round();
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= filled ? Icons.star : Icons.star_border,
            size: 16,
            color: AppColors.accentGold,
          ),
        const SizedBox(width: 6),
        Text(
          l10n.pdpRatingReviews(rating.toStringAsFixed(1), reviewCount),
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
        ),
      ],
    );
  }
}

/// Quantity stepper (− N +) shown above the Tabby promo (Figma).
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l10n.pdpQuantityLabel,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderDefault),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: quantity > 1 ? () => onChanged(quantity - 1) : null,
                icon: const Icon(Icons.remove, size: 18),
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(
                width: 32,
                child: Text(
                  '$quantity',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                onPressed: () => onChanged(quantity + 1),
                icon: const Icon(Icons.add, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Gallery extends ConsumerStatefulWidget {
  const _Gallery({
    required this.images,
    required this.sku,
    required this.urlKey,
    required this.badge,
    required this.discountPercent,
  });
  final List<String> images;
  final String sku;
  final String urlKey;
  final ProductBadge badge;
  final int? discountPercent;

  @override
  ConsumerState<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends ConsumerState<_Gallery> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _badgeLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (widget.badge) {
      ProductBadge.isNew => l10n.badgeNew,
      ProductBadge.bestseller => l10n.badgeBestseller,
      ProductBadge.none => null,
    };
  }

  /// Copies the product's canonical storefront URL. It must come from
  /// [productUrl] — a hand-built `hub-market.magento2.click/<url_key>` link has no `.html`
  /// suffix and no store path, so it 404s on the web and can't be resolved
  /// back into the app (CL042-DEV10).
  Future<void> _share(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final url = productUrl(ref.read(storeControllerProvider), widget.urlKey);
    if (url == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.actionLinkCopied)));
    }
  }

  /// Warm the images either side of the current page so a swipe is instant.
  /// Bounded to the neighbours — a 20-image gallery must not download itself.
  void _warmNeighbours() {
    if (!mounted) return;
    final images = widget.images;
    if (images.length < 2) return;
    final n = images.length;
    unawaited(
      prefetchImages(
        context,
        [images[(_index + 1) % n], images[(_index - 1 + n) % n]],
        decodeWidth: pdpImagePixels(context),
        limit: 2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    // The gallery spans the full screen width — decode at that size, not full
    // res. Shared with the pre-warm on tap so both hit the same cache key.
    final imageWidth = pdpImageWidth(context);
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: images.isEmpty
              ? Container(color: AppColors.surfaceTint)
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _controller,
                      itemCount: images.length,
                      onPageChanged: (i) {
                        setState(() => _index = i);
                        _warmNeighbours();
                      },
                      itemBuilder: (_, i) => HubImage(
                        url: images[i],
                        decodeWidth: imageWidth,
                        shimmer: true,
                      ),
                    ),
                    // Merchandising + discount badges (Figma) — top-start,
                    // mirroring the product card (NEW/BESTSELLER over -N%).
                    PositionedDirectional(
                      top: 12,
                      start: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_badgeLabel(context) != null)
                            _GalleryBadge(
                              label: _badgeLabel(context)!,
                              color: widget.badge == ProductBadge.bestseller
                                  ? AppColors.accentGold
                                  : AppColors.brandPrimary,
                            ),
                          if (_badgeLabel(context) != null &&
                              widget.discountPercent != null)
                            const SizedBox(height: 6),
                          if (widget.discountPercent != null)
                            _GalleryBadge(
                              label: '-${widget.discountPercent}%',
                              color: AppColors.accentSale,
                            ),
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      top: 8,
                      end: 8,
                      child: Column(
                        children: [
                          WishlistHeart(sku: widget.sku),
                          IconButton(
                            onPressed: () => _share(context),
                            icon: const Icon(
                              Icons.ios_share,
                              color: AppColors.inkHeading,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Page-dot indicator (Figma) — current image in the gallery.
                    if (images.length > 1)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < images.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: i == _index ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: i == _index
                                      ? AppColors.brandPrimary
                                      : AppColors.inkMuted.withValues(
                                          alpha: 0.35,
                                        ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        // Thumbnail strip beneath the main image (per Figma) — tap to switch.
        if (images.length > 1)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => _controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
                child: Container(
                  width: 56,
                  height: 56,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: i == _index
                          ? AppColors.brandPrimary
                          : AppColors.inkMuted.withValues(alpha: 0.25),
                      width: i == _index ? 2 : 1,
                    ),
                  ),
                  child: HubImage(url: images[i], decodeWidth: 56),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small pill badge over the PDP gallery image (Figma), matching the product
/// card's NEW/BESTSELLER/discount badge style.
class _GalleryBadge extends StatelessWidget {
  const _GalleryBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      textDirection: TextDirection.ltr,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.price,
    required this.product,
    required this.showStruck,
  });

  final Money? price;
  final ProductDetail product;
  final bool showStruck;

  @override
  Widget build(BuildContext context) {
    if (price == null) return const SizedBox.shrink();
    final regular = product.regularPrice;
    final showSale = showStruck && product.isOnSale && regular != null;
    final discount = showSale ? (product.discountPercent ?? 0) : 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          price!.formatted(),
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.brandPrimary,
          ),
        ),
        if (showSale) ...[
          const SizedBox(width: 12),
          Text(
            regular.formatted(),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              decoration: TextDecoration.lineThrough,
              color: AppColors.inkMuted,
            ),
          ),
          if (discount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.accentSale,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '-$discount%',
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _OptionSelector extends StatelessWidget {
  const _OptionSelector({
    required this.option,
    required this.selectedValue,
    required this.onSelect,
  });

  final ConfigurableOption option;
  final int? selectedValue;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            option.label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in option.values)
                ChoiceChip(
                  label: Text(value.label),
                  selected: selectedValue == value.valueIndex,
                  onSelected: (_) => onSelect(value.valueIndex),
                  avatar: value.swatchColor != null
                      ? CircleAvatar(
                          backgroundColor: _parseColor(value.swatchColor!),
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color? _parseColor(String hex) {
    final cleaned = hex.replaceAll('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onTab});
  final int current;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = [
      l10n.tabDetails,
      l10n.tabKeyFeatures,
      l10n.tabMoreInformation,
      l10n.tabReviews,
    ];
    // Four tabs matching the website (Details · Key Features · More Information ·
    // Reviews); the active one keeps its burgundy underline. Kept scrollable so
    // the four AR labels never overflow.
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.borderDefault),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              InkWell(
                onTap: () => onTab(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: current == i
                            ? AppColors.brandPrimary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: current == i
                          ? AppColors.brandPrimary
                          : AppColors.inkMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sticky bottom Add-to-Cart bar (Figma): wishlist heart + a full-width button
/// showing "Add to Cart · price". Recomputes the variant/price from the live
/// swatch selection.
class _StickyAddToCart extends ConsumerWidget {
  const _StickyAddToCart({
    required this.product,
    required this.selection,
    required this.quantity,
  });

  final ProductDetail product;
  final Map<String, int> selection;
  final int quantity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final variant = product.variantFor(selection);
    final price = variant?.price ?? product.finalPrice ?? product.regularPrice;
    final inStock = variant?.inStock ?? product.inStock;
    final needsSelection = product.isConfigurable && variant == null;
    final isMutating = ref.watch(
      cartControllerProvider.select((s) => s.isMutating),
    );
    final enabled = inStock && !needsSelection && !isMutating;

    // No SafeArea here — this bar sits *above* the bottom nav, which already
    // applies the system bottom inset. Wrapping it again added a large empty
    // gap below the button.
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: context.hairline),
                borderRadius: BorderRadius.circular(12),
              ),
              // Dark mode: the default ink heart was invisible on the dark bar
              // (QA "Add to Wishlist icon on the product page").
              child: WishlistHeart(
                sku: product.sku,
                color: context.scaffoldHeading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: enabled ? () => _add(context, ref, l10n) : null,
                child: isMutating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        !inStock
                            ? l10n.productOutOfStock
                            : price == null
                            ? l10n.productAddToCart
                            : '${l10n.productAddToCart} · ${price.formatted()}',
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final uids = <String>[];
    for (final option in product.options) {
      final selectedIndex = selection[option.attributeCode];
      for (final value in option.values) {
        if (value.valueIndex == selectedIndex && value.uid != null) {
          uids.add(value.uid!);
        }
      }
    }
    try {
      await ref
          .read(cartControllerProvider.notifier)
          .addToCart(
            sku: product.sku,
            quantity: quantity,
            selectedOptionUids: uids,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.cartAdded)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      }
    }
  }
}

/// Compact trust row on the PDP (Figma): authenticity, delivery, service.
class _TrustRow extends ConsumerWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // The free-shipping caption follows the real store threshold (never
    // hardcoded); falls back to a neutral label while it loads / if unset.
    final threshold = ref.watch(freeShippingThresholdProvider).valueOrNull;
    final freeLabel = threshold != null
        ? l10n.pdpTrustFreeOver(threshold.round())
        : l10n.pdpTrustFreeLabel;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        // Top-align so the three seals line up at the top even when one caption
        // (e.g. the AR delivery line) wraps to more rows than the others.
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TrustItem(
            icon: Icons.verified_user_outlined,
            value: l10n.pdpTrustAuthenticValue,
            label: l10n.pdpTrustAuthenticLabel,
          ),
          _TrustItem(
            icon: Icons.local_shipping_outlined,
            value: l10n.pdpTrustFreeValue,
            label: freeLabel,
          ),
          _TrustItem(
            icon: Icons.schedule,
            value: l10n.pdpTrustDeliveryValue,
            label: l10n.pdpTrustDeliveryLabel,
          ),
        ],
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, color: AppColors.brandPrimary, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.inkHeading,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
        ),
      ],
    ),
  );
}

/// Reviews summary block (Figma): big average, star row, total count, and
/// per-star distribution bars derived from the loaded reviews.
class _ReviewsSummary extends StatelessWidget {
  const _ReviewsSummary({required this.product});
  final ProductDetail product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final average = product.ratingSummary / 20; // 0–5
    // Per-star bars (5★ → 1★) derived from the loaded reviews — Magento core
    // has no histogram field. Bar lengths use each bucket's percent.
    final byStar = <int, RatingBar>{
      for (final b in product.ratingHistogram) b.stars: b,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          children: [
            Text(
              average.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w700,
                color: AppColors.inkHeading,
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    i <= average.round() ? Icons.star : Icons.star_border,
                    size: 14,
                    color: AppColors.accentGold,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.reviewsCount(product.reviewCount),
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(width: 20),
        // Per-star bars, 5★ at the top.
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text(
                        '$star',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (byStar[star]?.percent ?? 0) / 100,
                            minHeight: 6,
                            backgroundColor: AppColors.surfaceMuted,
                            valueColor: const AlwaysStoppedAnimation(
                              AppColors.accentGold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 20,
                        child: Text(
                          '${byStar[star]?.count ?? 0}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final ProductReview review;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar with initials (Figma) — derived from the reviewer name.
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.surfaceTint,
                child: Text(
                  _initials(review.nickname),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  review.nickname,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (review.date.isNotEmpty)
                Text(
                  review.date,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= review.stars ? Icons.star : Icons.star_border,
                  size: 16,
                  color: AppColors.accentGold,
                ),
            ],
          ),
          if (review.summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.summary,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (review.text.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              review.text,
              style: const TextStyle(color: AppColors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({required this.product, required this.tab});
  final ProductDetail product;
  final int tab;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    switch (tab) {
      // Key Features: the marketing short description (website "Key Features").
      case 1:
        return Text(
          (product.shortDescription ?? '').isNotEmpty
              ? product.shortDescription!
              : l10n.stateEmpty,
        );
      // More Information: storefront-visible attributes + SKU.
      case 2:
        return _MoreInformation(product: product);
      // Reviews.
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (product.hasReviews) ...[
              _ReviewsSummary(product: product),
              const SizedBox(height: 16),
              for (final review in product.reviews) _ReviewCard(review: review),
            ] else ...[
              Text(
                l10n.reviewsEmptyTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.reviewsEmptyBody,
                style: const TextStyle(color: AppColors.inkMuted),
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.review(product.sku)),
              icon: const Icon(Icons.rate_review_outlined),
              label: Text(l10n.reviewsWrite),
            ),
          ],
        );
      // Details: the full product description (website "Details").
      case 0:
      default:
        return Text(
          (product.description ?? '').isNotEmpty
              ? product.description!
              : l10n.stateEmpty,
        );
    }
  }
}

/// PDP "More Information" tab — a compact key/value table of the storefront-
/// visible product attributes (Magento `custom_attributesV2`, mirroring the
/// website's product-details table), always including the SKU. Renders whatever
/// the catalogue exposes; no fabricated rows.
class _MoreInformation extends StatelessWidget {
  const _MoreInformation({required this.product});
  final ProductDetail product;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <(String, String)>[
      for (final attr in product.attributes)
        (_label(l10n, attr.code), attr.value),
      (l10n.specSku, product.sku),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, color: AppColors.borderDefault),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    rows[i].$1,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(rows[i].$2)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Localized row label for a known attribute code; unknown codes are
  /// prettified from snake_case so new catalogue attributes still read cleanly.
  String _label(AppLocalizations l10n, String code) {
    switch (code) {
      case 'manufacturer':
        return l10n.attrBrand;
      default:
        return code
            .split('_')
            .where((w) => w.isNotEmpty)
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');
    }
  }
}
