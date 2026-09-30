import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/widgets/added_to_cart_sheet.dart';
import '../../../home/presentation/home_providers.dart';
import '../../../home/presentation/widgets/hm_cms_sections.dart';
import '../../../marketplace/marketplace_features.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../../wishlist/presentation/widgets/wishlist_heart.dart';
import '../../data/brands_provider.dart';
import '../../domain/money.dart';
import '../../domain/product.dart';
import '../../domain/product_detail.dart';
import '../../domain/product_preview.dart';
import '../brand_navigation.dart';
import '../catalog_providers.dart';
import '../product_navigation.dart';
import '../widgets/product_card.dart';
import '../widgets/product_skeletons.dart';
import '../widgets/review_widgets.dart';
import 'bundle_product_screen.dart';

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
    // HubApp's additions (P3): who sells it, and a bundle's options. Null —
    // today's page — without HubApp.
    final marketplace = ref.watch(productMarketplaceProvider(widget.urlKey));
    final bundlesOn = ref.watch(
      marketplaceFeaturesProvider.select((f) => f.bundles),
    );
    final loaded = detail.valueOrNull;
    final extras = marketplace.valueOrNull;
    // Figma 14b: a bundle builds its package on its own page.
    if (loaded != null && bundlesOn && extras?.bundle != null) {
      return BundleProductScreen(
        product: loaded,
        bundle: extras!.bundle!,
        seller: extras.seller,
      );
    }
    // A bundle's options are still on their way: keep the skeleton up rather
    // than flash the plain page first.
    final awaitingBundle =
        loaded != null && loaded.isBundle && bundlesOn && marketplace.isLoading;

    return HubScaffold(
      currentTab: AppTab.home,
      // Sticky Add-to-Cart bar (Figma) pinned above the bottom nav — shown once
      // the product has loaded, and retracted as the footer scrolls into view.
      bottomBar: detail.maybeWhen(
        data: (product) => (product == null || !_showBar || awaitingBundle)
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
          if (awaitingBundle) {
            return ProductDetailSkeleton(preview: widget.preview);
          }
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
            seller: extras?.seller,
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
    this.seller,
  });

  final ProductDetail product;

  /// Who sells it (HubApp); the "Sold by" row is left out without one, and
  /// for Hub Market's own products.
  final HmSellerSummary? seller;
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
    final soldBy = seller;

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.zero,
      children: [
        ProductGallery(
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
              // Figma 14 "Sold by" (16:1020), above the title.
              if (soldBy != null && !soldBy.isMarketplace) ...[
                SoldByRow(seller: soldBy),
                const SizedBox(height: 14),
              ],
              if (product.brand != null && product.brand!.isNotEmpty)
                _BrandLink(
                  name: product.brand!,
                  optionId: product.brandOptionId,
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
                  onTap: () =>
                      context.push(AppRoutes.productReviews(product.urlKey)),
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
              const PdpTrustRow(),
              const SizedBox(height: 24),
              _Tabs(current: tab, onTab: onTab),
              const SizedBox(height: 12),
              _TabContent(product: product, tab: tab),
            ],
          ),
        ),
        _RelatedProducts(products: product.alsoLike),
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

/// The brand line above the title: a link to the brand's page, or its
/// products (see [openProductBrand]).
class _BrandLink extends ConsumerWidget {
  const _BrandLink({required this.name, this.optionId});

  final String name;
  final int? optionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Warms the brand list (Hub Market App only; empty at once without it),
    // so a tap opens the brand page without waiting for it.
    ref.watch(brandsProvider);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: InkWell(
        onTap: () => openProductBrand(
          context,
          ref,
          name: name,
          optionId: optionId,
        ),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: 2, bottom: 2, end: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: const TextStyle(
                    color: AppColors.brandPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppColors.brandPrimary,
              ),
            ],
          ),
        ),
      ),
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

/// Star + "4.6 · N reviews" line under the product title (Figma); opens the
/// Reviews screen.
class _RatingLine extends StatelessWidget {
  const _RatingLine({
    required this.ratingSummary,
    required this.reviewCount,
    required this.onTap,
  });

  /// 0–100 (Magento `rating_summary`).
  final int ratingSummary;
  final int reviewCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rating = ratingSummary / 20; // 0–5
    final filled = rating.round();
    return InkWell(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }
}

/// Quantity stepper (− N +) under the options (Figma).
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

/// The product page's image gallery: swipeable images with page dots and a
/// thumbnail strip, merchandising badges, wishlist and share. The bundle page
/// (Figma 14b) shows its own badges along the bottom through [bottomBadges].
class ProductGallery extends ConsumerStatefulWidget {
  const ProductGallery({
    super.key,
    required this.images,
    required this.sku,
    required this.urlKey,
    this.badge = ProductBadge.none,
    this.discountPercent,
    this.bottomBadges = const <Widget>[],
  });
  final List<String> images;
  final String sku;
  final String urlKey;
  final ProductBadge badge;
  final int? discountPercent;

  /// Pills along the image's bottom-start edge.
  final List<Widget> bottomBadges;

  @override
  ConsumerState<ProductGallery> createState() => _GalleryState();
}

class _GalleryState extends ConsumerState<ProductGallery> {
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
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: Container(color: AppColors.surfaceTint),
                    ),
                    if (widget.bottomBadges.isNotEmpty)
                      PositionedDirectional(
                        start: 16,
                        end: 16,
                        bottom: 12,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.bottomBadges,
                        ),
                      ),
                  ],
                )
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
                            GalleryBadge(
                              label: _badgeLabel(context)!,
                              color: widget.badge == ProductBadge.bestseller
                                  ? AppColors.accentGold
                                  : AppColors.brandPrimary,
                            ),
                          if (_badgeLabel(context) != null &&
                              widget.discountPercent != null)
                            const SizedBox(height: 6),
                          if (widget.discountPercent != null)
                            GalleryBadge(
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
                    if (widget.bottomBadges.isNotEmpty)
                      PositionedDirectional(
                        start: 16,
                        end: 16,
                        // Above the page dots when there are some.
                        bottom: images.length > 1 ? 30 : 12,
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.bottomBadges,
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
class GalleryBadge extends StatelessWidget {
  const GalleryBadge({
    super.key,
    required this.label,
    required this.color,
    this.textDirection = TextDirection.ltr,
  });
  final String label;
  final Color color;

  /// LTR for bare figures ("-24%"); worded labels follow the locale.
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      textDirection: textDirection,
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
    // Reviews); the active one keeps its navy underline. Kept scrollable so
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
///
/// A bundle reaches this plain page only when its own page (Figma 14b) can't
/// be used — Build 1, or its options couldn't be read. Its SKU alone is
/// refused by Magento, so the button stays off and a note sends the customer
/// to the bundle on the website.
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
    final webOnly = product.isBundle;
    final isMutating = ref.watch(
      cartControllerProvider.select((s) => s.isMutating),
    );
    final enabled = inStock && !needsSelection && !webOnly && !isMutating;

    // No SafeArea here — this bar sits *above* the bottom nav, which already
    // applies the system bottom inset. Wrapping it again added a large empty
    // gap below the button.
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (webOnly && inStock) _BundleOnWebsiteNote(product: product),
            _barRow(context, ref, l10n, price, inStock, enabled, isMutating),
          ],
        ),
      ),
    );
  }

  Widget _barRow(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
    Money? price,
    bool inStock,
    bool enabled,
    bool isMutating,
  ) => Row(
    children: [
      Container(
        decoration: BoxDecoration(
          border: Border.all(color: context.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        // Dark mode: the default ink heart was invisible on the dark bar
        // (QA "Add to Wishlist icon on the product page").
        child: WishlistHeart(sku: product.sku, color: context.scaffoldHeading),
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
  );

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
        AddedToCartSheet.show(
          context,
          item: AddedItem.fromDetail(product, selection, quantity),
          recommendations: product.alsoLike,
        );
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

/// Over a bundle's disabled Add to Cart: it is bought on the website for now,
/// with a button that opens its storefront page in the browser.
class _BundleOnWebsiteNote extends ConsumerWidget {
  const _BundleOnWebsiteNote({required this.product});

  final ProductDetail product;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    // The canonical storefront URL of the active store view (its language
    // path and `.html`), as Share uses — once the store views are known.
    await ref.read(storeControllerProvider.notifier).ensureStoresLoaded();
    if (!context.mounted) return;
    final url = productUrl(ref.read(storeControllerProvider), product.urlKey);
    final uri = url == null ? null : Uri.tryParse(url);
    final opened =
        uri != null && await ref.read(externalUriLauncherProvider)(uri);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.pdpBundleOnWebsite,
              style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _open(context, ref),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text(l10n.pdpBundleOpenWebsite),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentStrong,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact trust row on the PDP (Figma 14): the storefront's own trust items,
/// from the CMS block `hm_home_trust` (Content › Blocks) that the Home and the
/// website show — so marketing edits them once, and the page promises only
/// what the store says (no "Free Delivery" the store never offered). Hidden
/// when the block is empty, disabled or unreadable (QA02).
class PdpTrustRow extends ConsumerWidget {
  const PdpTrustRow({super.key});

  /// Items across the row, as in the Figma; more scroll sideways.
  static const int across = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(homeTrustProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Up to three share the width; beyond that the next one peeks in
            // at the edge, so the row reads as scrollable.
            final width = items.length <= across
                ? constraints.maxWidth / items.length
                : constraints.maxWidth / (across + 0.4);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                // Top-align so the seals line up even when one caption wraps
                // to more lines than the others.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < items.length; i++)
                    SizedBox(
                      width: width,
                      child: _TrustItem(
                        icon: HmTrustGrid.iconFor(items[i], i),
                        title: items[i].title,
                        text: items[i].text,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Column(
      children: [
        Icon(icon, color: AppColors.brandPrimary, size: 22),
        const SizedBox(height: 6),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.inkHeading,
          ),
        ),
        if (text.isNotEmpty)
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
          ),
      ],
    ),
  );
}

/// Reviews the product page shows before "See all".
const int _pdpReviewPreview = 3;

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
      // Reviews: the summary, the newest few, and "See all" for the rest
      // (Figma 14 → 15). Bars only when every review is here — see
      // ProductDetail.ratingHistogram.
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (product.hasReviews) ...[
              ReviewsSummaryCard(
                ratingSummary: product.ratingSummary,
                reviewCount: product.reviewCount,
                histogram: product.ratingHistogram,
              ),
              for (final review in product.reviews.take(_pdpReviewPreview))
                ReviewCard(review: review),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () =>
                      context.push(AppRoutes.productReviews(product.urlKey)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentStrong,
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    l10n.reviewsSeeAll(product.reviewCount),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
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
      for (final attr in product.attributes) (_label(l10n, attr), attr.value),
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

  /// Localized row label for the brand attribute; other codes are prettified
  /// from snake_case so new catalogue attributes still read cleanly.
  String _label(AppLocalizations l10n, ProductAttribute attr) {
    if (attr.isBrand) return l10n.attrBrand;
    return attr.code
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}
