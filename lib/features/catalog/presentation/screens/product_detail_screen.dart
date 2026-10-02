import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/not_found_state.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/presentation/cart_controller.dart';
import '../../../cart/presentation/widgets/added_to_cart_sheet.dart';
import '../../../home/presentation/home_providers.dart';
import '../../../marketplace/domain/product_offer.dart';
import '../../../marketplace/marketplace_features.dart';
import '../../../marketplace/presentation/other_sellers.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../../personalization/data/insights_tracker.dart';
import '../../data/brands_provider.dart';
import '../../domain/product.dart';
import '../../domain/product_detail.dart';
import '../../domain/product_marketplace.dart';
import '../../domain/product_preview.dart';
import '../../domain/review_subject.dart';
import '../brand_navigation.dart';
import '../catalog_providers.dart';
import '../low_stock_text.dart';
import '../widgets/pdp_buy_bar.dart';
import '../widgets/pdp_sections.dart';
import '../widgets/product_gallery.dart';
import '../widgets/product_skeletons.dart';
import 'bundle_product_screen.dart';

export '../widgets/pdp_sections.dart' show PdpTrustRow;

/// Figma 14 — the product page. There is no app bar: a full-bleed photo
/// gallery carries the round back / share / wishlist / cart buttons, then come
/// the seller, the title, the rating, the price and the choices (colour, size),
/// the other sellers' offers, the delivery promises, the description and
/// specifications, the reviews and the similar products; a sticky buy bar
/// (quantity and "Add to cart") stays at the bottom.
///
/// What the frame draws and the backend cannot back is left out, not made up:
/// the Tabby / Tamara block (the store has neither), the "Delivery by" date (no
/// delivery estimate), the size guide, "Verified purchase" and "Frequently
/// bought together". See `docs/ui-audit.md`.
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
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    // "Viewed Product" for Algolia Personalization, once the product has
    // loaded (the tracker counts a page opened twice in a row as one view).
    ref.listenManual(productDetailProvider(widget.urlKey), (_, next) {
      final detail = next.valueOrNull;
      if (detail == null) return;
      trackInsights(
        () => ref.read(insightsTrackerProvider),
        (tracker) => tracker.productViewed(detail.sku),
      );
    }, fireImmediately: true);
  }

  /// "Compare": the sheet of every other seller's offer. An offer is added to
  /// the cart the way this page adds — with this page's quantity — or opened on
  /// its own page, where one bought with options is chosen.
  Future<void> _compare(
    ProductDetail product,
    ProductMarketplace extras,
  ) async {
    final choice = await OtherSellersSheet.show(
      context,
      count: extras.offerCount,
      offers: extras.offers,
    );
    if (choice == null || !mounted) return;
    await _useOffer(product, choice.offer, add: choice.add);
  }

  Future<void> _useOffer(
    ProductDetail product,
    ProductOffer offer, {
    required bool add,
  }) async {
    if (!add || !offer.addsDirectly) {
      unawaited(context.push(AppRoutes.product(offer.urlKey)));
      return;
    }
    await _addAndConfirm(
      context,
      ref,
      sku: offer.sku,
      quantity: _quantity,
      item: AddedItem(
        name: product.name,
        quantity: _quantity,
        imageUrl: product.gallery.isEmpty ? null : product.gallery.first,
        unitPrice: offer.price,
      ),
      recommendations: product.alsoLike,
    );
  }

  /// The chosen options' uids, for `addProductsToCart`.
  List<String> _selectedUids(ProductDetail product) {
    final uids = <String>[];
    for (final option in product.options) {
      final selectedIndex = _selection[option.attributeCode];
      for (final value in option.values) {
        if (value.valueIndex == selectedIndex && value.uid != null) {
          uids.add(value.uid!);
        }
      }
    }
    return uids;
  }

  Future<void> _add(ProductDetail product) => _addAndConfirm(
    context,
    ref,
    sku: product.sku,
    quantity: _quantity,
    selectedOptionUids: _selectedUids(product),
    item: AddedItem.fromDetail(product, _selection, _quantity),
    recommendations: product.alsoLike,
  );

  /// The sticky bar (Figma "Buy bar"): quantity, and "Add to cart · price",
  /// recomputed from the live selection.
  ///
  /// A bundle reaches this plain page only when its own page (Figma 14b) can't
  /// be used — Build 1, or its options couldn't be read. Its SKU alone is
  /// refused by Magento, so the button stays off and a note sends the customer
  /// to the bundle on the website.
  Widget _buyBar(ProductDetail product) {
    final l10n = AppLocalizations.of(context);
    final variant = product.variantFor(_selection);
    final price = variant?.price ?? product.finalPrice ?? product.regularPrice;
    final inStock = variant?.inStock ?? product.inStock;
    final needsSelection = product.isConfigurable && variant == null;
    final webOnly = product.isBundle;
    final isMutating = ref.watch(
      cartControllerProvider.select((s) => s.isMutating),
    );
    final enabled = inStock && !needsSelection && !webOnly;
    return PdpBuyBar(
      quantity: _quantity,
      onQuantity: (value) => setState(() => _quantity = value),
      busy: isMutating,
      label: !inStock
          ? l10n.productOutOfStock
          : price == null
          ? l10n.pdpAddToCart
          : '${l10n.pdpAddToCart} · ${price.formatted()}',
      onPressed: enabled ? () => _add(product) : null,
      note: webOnly && inStock ? _BundleOnWebsiteNote(product: product) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
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
    final product = awaitingBundle ? null : loaded;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status-bar icons over the light photo stage.
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        // The sticky buy bar (Figma "Buy bar"): once the product has loaded.
        bottomNavigationBar: product == null ? null : _buyBar(product),
        body: AsyncValueView(
          value: detail,
          loading: () => _withBack(ProductDetailSkeleton(preview: widget.preview)),
          onRetry: () => ref.invalidate(productDetailProvider(widget.urlKey)),
          data: (data) {
            if (awaitingBundle) {
              return _withBack(ProductDetailSkeleton(preview: widget.preview));
            }
            if (data == null) {
              // A stale or rewritten link lands here — Figma S7, with a way
              // out rather than a bare string in the middle of the page.
              return _withBack(const NotFoundState());
            }
            final offers = extras?.offers ?? const <ProductOffer>[];
            return _Content(
              product: data,
              seller: extras?.seller,
              // Figma 14 "Sold by N other sellers" (HubApp): the other
              // sellers' offers on this product.
              offerCount: offers.isEmpty ? 0 : extras!.offerCount,
              offers: offers,
              selection: _selection,
              onSelect: (code, value) =>
                  setState(() => _selection[code] = value),
              onCompare: () {
                if (extras != null && offers.isNotEmpty) _compare(data, extras);
              },
              onOpenOffer: (offer) => _useOffer(data, offer, add: false),
              onAddOffer: (offer) => _useOffer(data, offer, add: true),
            );
          },
        ),
      ),
    );
  }

  /// A page with no gallery of its own yet — loading, not found, failed — still
  /// offers the round back button, where the gallery's will be. (The error and
  /// offline states, drawn by [AsyncValueView], get it from the same call.)
  Widget _withBack(Widget page) => Stack(
    children: [
      Positioned.fill(child: page),
      PositionedDirectional(
        top: MediaQuery.paddingOf(context).top + 5,
        start: 16,
        child: OverPhotoButton(
          icon: HubIcons.arrowLeft,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => popOrHome(context),
        ),
      ),
    ],
  );
}

/// The loaded page: the gallery, then the blocks of Figma 14 — 14 px apart,
/// inside a 16 px gutter — and the similar-products rail, which runs to the
/// screen edges.
class _Content extends ConsumerWidget {
  const _Content({
    required this.product,
    required this.selection,
    required this.onSelect,
    required this.onCompare,
    required this.onOpenOffer,
    required this.onAddOffer,
    this.seller,
    this.offerCount = 0,
    this.offers = const <ProductOffer>[],
  });

  final ProductDetail product;

  /// Who sells it (HubApp); the "Sold by" card is left out without one, and
  /// for Hub Market's own products.
  final HmSellerSummary? seller;

  /// How many other sellers offer it (HubApp), with their [offers] and
  /// [onCompare] (the sheet with all of them): the "Sold by N other sellers"
  /// card.
  final int offerCount;
  final List<ProductOffer> offers;
  final VoidCallback onCompare;
  final ValueChanged<ProductOffer> onOpenOffer;
  final ValueChanged<ProductOffer> onAddOffer;
  final Map<String, int> selection;
  final void Function(String code, int value) onSelect;

  static List<Widget> _spaced(List<Widget> blocks) => [
    for (var i = 0; i < blocks.length; i++) ...[
      if (i > 0) const SizedBox(height: 14),
      blocks[i],
    ],
  ];

  /// Whether some variant in stock has [value] of [option], given what the
  /// other options picked. Without variants everything is available.
  bool _available(ConfigurableOption option, SwatchValue value) {
    if (product.variants.isEmpty) return true;
    return product.variants.any(
      (v) =>
          v.inStock &&
          v.attributes[option.attributeCode] == value.valueIndex &&
          selection.entries.every(
            (e) => e.key == option.attributeCode || v.attributes[e.key] == e.value,
          ),
    );
  }

  /// Localized row label for the brand attribute; other codes are prettified
  /// from snake_case so new catalogue attributes still read cleanly.
  static String _specLabel(AppLocalizations l10n, ProductAttribute attr) {
    if (attr.isBrand) return l10n.attrBrand;
    return attr.code
        .split('_')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final variant = product.variantFor(selection);
    final price = variant?.price ?? product.finalPrice ?? product.regularPrice;
    final regular = product.regularPrice;
    final showSale = variant == null && product.isOnSale && regular != null;
    final inStock = variant?.inStock ?? product.inStock;
    final images = <String>[
      if (variant?.imageUrl != null) variant!.imageUrl!,
      ...product.gallery,
    ];
    final soldBy = seller;
    final left = inStock ? product.onlyLeftFor(selection) : null;
    final lowStock = left == null
        ? null
        : lowStockText(l10n, left, product.stockOptionLabel(selection));
    final delivery = PdpTrustRow.rowsOf(ref.watch(homeTrustProvider));
    final specs = <(String, String)>[
      for (final attr in product.attributes)
        (_specLabel(l10n, attr), attr.value),
      (l10n.specSku, product.sku),
    ];
    final description = product.description ?? '';
    final features = product.shortDescription ?? '';
    final category = product.primaryCategory;
    final rail = product.alsoLike.isNotEmpty;

    final blocks = <Widget>[
      // Figma 14 "sold-by" (16:1020), above the title.
      if (soldBy != null && !soldBy.isMarketplace) SoldByRow(seller: soldBy),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (product.brand != null && product.brand!.isNotEmpty) ...[
            _BrandLink(name: product.brand!, optionId: product.brandOptionId),
            const SizedBox(height: 4),
          ],
          Text(
            product.name,
            style: t.heading1.copyWith(color: AppColors.inkHeading),
          ),
        ],
      ),
      PdpRatingRow(
        ratingSummary: product.ratingSummary,
        reviewCount: product.reviewCount,
        inStock: inStock,
        onReviews: () =>
            context.push(AppRoutes.productReviews(product.urlKey)),
      ),
      if (price != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: PdpPriceRow(
            price: price.formatted(),
            regularPrice: showSale ? regular.formatted() : null,
            showSale: showSale,
          ),
        ),
      if (product.options.isNotEmpty || lowStock != null) ...[
        const Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < product.options.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              PdpOptionPicker(
                option: product.options[i],
                selectedValue: selection[product.options[i].attributeCode],
                onSelect: (value) =>
                    onSelect(product.options[i].attributeCode, value),
                isAvailable: (value) => _available(product.options[i], value),
              ),
            ],
            if (lowStock != null) ...[
              SizedBox(height: product.options.isEmpty ? 0 : 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: PdpLowStockLine(text: lowStock),
              ),
            ],
          ],
        ),
      ],
      if (offerCount > 0 && offers.isNotEmpty)
        OtherSellersCard(
          count: offerCount,
          offers: offers,
          onCompare: onCompare,
          onOpen: onOpenOffer,
          onAdd: onAddOffer,
        ),
      if (delivery.isNotEmpty) PdpTrustRow(rows: delivery),
      if (description.isNotEmpty || features.isNotEmpty)
        PdpAccordion(
          title: l10n.pdpDescriptionMaterial,
          topRule: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (description.isNotEmpty) PdpParagraph(description),
              if (features.isNotEmpty) ...[
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      l10n.tabKeyFeatures,
                      style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                    ),
                  ),
                PdpParagraph(features),
              ],
            ],
          ),
        ),
      PdpAccordion(
        title: l10n.pdpSpecifications,
        initiallyOpen: true,
        chevronSize: 18,
        chevronColor: AppColors.inkMuted,
        verticalPadding: 4,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: PdpSpecRows(rows: specs),
        ),
      ),
      PdpReviewsSection(
        product: product,
        onSeeAll: () => context.push(AppRoutes.productReviews(product.urlKey)),
        onWrite: () => context.push(
          AppRoutes.review(product.sku),
          extra: ReviewSubject(
            sku: product.sku,
            name: product.name,
            imageUrl: images.isEmpty ? null : images.first,
            sellerName: soldBy == null || soldBy.isMarketplace
                ? null
                : soldBy.name,
          ),
        ),
      ),
    ];

    return ListView(
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
          padding: EdgeInsets.fromLTRB(16, 16, 16, rail ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _spaced(blocks),
          ),
        ),
        PdpSimilarRail(
          products: product.alsoLike,
          onSeeAll: category == null
              ? null
              : () => context.push(
                  AppRoutes.category(category.uid),
                  extra: category.name,
                ),
        ),
        if (rail) const SizedBox(height: 16),
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
        onTap: () =>
            openProductBrand(context, ref, name: name, optionId: optionId),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(top: 2, bottom: 2, end: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  name,
                  style: AppTextStyles.of(
                    context,
                  ).captionStrong.copyWith(color: AppColors.brandPrimary),
                ),
              ),
              const Icon(
                HubIcons.chevronRight,
                size: 14,
                color: AppColors.brandPrimary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How the product page adds to the cart — its own product from the sticky
/// bar, or another seller's offer from the other-sellers card: [sku] into
/// the cart, then "Added to cart" (14c) with [item], or the error.
Future<void> _addAndConfirm(
  BuildContext context,
  WidgetRef ref, {
  required String sku,
  required int quantity,
  required AddedItem item,
  List<String> selectedOptionUids = const [],
  List<Product> recommendations = const [],
}) async {
  final l10n = AppLocalizations.of(context);
  try {
    await ref
        .read(cartControllerProvider.notifier)
        .addToCart(
          sku: sku,
          quantity: quantity,
          selectedOptionUids: selectedOptionUids,
        );
    if (context.mounted) {
      AddedToCartSheet.show(
        context,
        item: item,
        recommendations: recommendations,
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
    final t = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Icon(HubIcons.info, size: 16, color: AppColors.inkMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.pdpBundleOnWebsite,
              style: t.caption.copyWith(color: AppColors.inkMuted),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _open(context, ref),
            icon: const Icon(HubIcons.externalLink, size: 16),
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
