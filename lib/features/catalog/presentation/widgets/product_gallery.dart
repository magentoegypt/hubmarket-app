import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import '../../../../core/util/image_prefetch.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../wishlist/presentation/wishlist_controller.dart';
import '../../domain/product.dart';
import '../product_navigation.dart';

/// Figma 14 / 14b "Gallery": a full-bleed photo stage (400 high on the product
/// page, 300 on a bundle's) on `bg/muted`, the photo contained in it, with the
/// round white buttons over it — back at the start, share, wishlist and cart at
/// the end — a "1 / 4" counter and the pager dots along the bottom. There is no
/// app bar: the buttons sit under the status bar, 5 px below it, and scroll away
/// with the photo.
///
/// Merchandising pills (NEW, -N%) and a bundle's own ([bottomBadges]) sit along
/// the bottom start edge, as 14b draws its "-16% BUNDLE" and "SAVE AED 11".
class ProductGallery extends ConsumerStatefulWidget {
  const ProductGallery({
    super.key,
    required this.images,
    required this.sku,
    required this.urlKey,
    this.badge = ProductBadge.none,
    this.discountPercent,
    this.bottomBadges = const <Widget>[],
    this.height = defaultHeight,
    this.showCart = true,
  });

  /// 400 px on the product page (Figma 14).
  static const double defaultHeight = 400;

  /// 300 px on a bundle's page (Figma 14b).
  static const double bundleHeight = 300;

  final List<String> images;
  final String sku;
  final String urlKey;
  final ProductBadge badge;
  final int? discountPercent;

  /// Pills along the stage's bottom start edge, after NEW and the discount.
  final List<Widget> bottomBadges;
  final double height;

  /// The cart button of the product page; a bundle's frame has none.
  final bool showCart;

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

  String? _badgeLabel(AppLocalizations l10n) => switch (widget.badge) {
    ProductBadge.isNew => l10n.badgeNew,
    ProductBadge.bestseller => l10n.badgeBestseller,
    ProductBadge.none => null,
  };

  /// Copies the product's canonical storefront URL. It must come from
  /// [productUrl] — a hand-built `hub-market.magento2.click/<url_key>` link has no `.html`
  /// suffix and no store path, so it 404s on the web and can't be resolved
  /// back into the app (CL042-DEV10).
  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = productUrl(ref.read(storeControllerProvider), widget.urlKey);
    if (url == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.actionLinkCopied)));
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
    final l10n = AppLocalizations.of(context);
    final images = widget.images;
    // The status bar overlays the photo; the buttons sit 5 px under it.
    final buttonsTop = MediaQuery.paddingOf(context).top + 5;
    final label = _badgeLabel(l10n);
    final discount = widget.discountPercent;
    final hasBadges =
        label != null || discount != null || widget.bottomBadges.isNotEmpty;
    // Dots up to a handful of photos; the counter alone beyond that.
    final dots = images.length > 1 && images.length <= 8;

    return SizedBox(
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.surfaceSubtle),
          if (images.isNotEmpty)
            PageView.builder(
              controller: _controller,
              itemCount: images.length,
              onPageChanged: (i) {
                setState(() => _index = i);
                _warmNeighbours();
              },
              // The gallery spans the full screen width — decode at that size,
              // not full res. Shared with the pre-warm on tap so both hit the
              // same cache key.
              itemBuilder: (_, i) => HubImage(
                url: images[i],
                fit: BoxFit.contain,
                decodeWidth: pdpImageWidth(context),
                shimmer: true,
                placeholder: (_) =>
                    const ColoredBox(color: AppColors.surfaceSubtle),
              ),
            ),
          if (hasBadges)
            PositionedDirectional(
              start: 16,
              bottom: 14,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (label != null)
                    GalleryBadge(
                      label: label,
                      color: widget.badge == ProductBadge.bestseller
                          ? AppColors.accentGold
                          : AppColors.brandPrimary,
                      textColor: widget.badge == ProductBadge.bestseller
                          ? AppColors.inkHeading
                          : Colors.white,
                    ),
                  if (discount != null)
                    GalleryBadge(
                      label: '-$discount%',
                      color: AppColors.accentSale,
                    ),
                  ...widget.bottomBadges,
                ],
              ),
            ),
          if (dots)
            PositionedDirectional(
              start: 0,
              end: 0,
              bottom: 18,
              child: Center(
                child: _Pager(count: images.length, index: _index),
              ),
            ),
          if (images.length > 1)
            PositionedDirectional(
              end: 16,
              bottom: 18,
              child: _Counter(index: _index, count: images.length),
            ),
          PositionedDirectional(
            top: buttonsTop,
            start: 16,
            child: OverPhotoButton(
              icon: HubIcons.arrowLeft,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => popOrHome(context),
            ),
          ),
          PositionedDirectional(
            top: buttonsTop,
            end: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OverPhotoButton(
                  icon: HubIcons.share2,
                  tooltip: l10n.actionShare,
                  onPressed: _share,
                ),
                const SizedBox(width: 8),
                _HeartButton(sku: widget.sku),
                if (widget.showCart) ...[
                  const SizedBox(width: 8),
                  OverPhotoButton(
                    icon: HubIcons.shoppingCart,
                    tooltip: l10n.navCart,
                    onPressed: () => context.push(AppRoutes.cart),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Back to where the customer came from; a page opened from a link with nothing
/// behind it goes to Home.
void popOrHome(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null || router.canPop()) {
    Navigator.of(context).maybePop();
  } else {
    router.go(AppRoutes.home);
  }
}

/// Figma "icon-btn/…" over a photo: the 40 px round button on a white disc with
/// the frame's soft drop shadow (0 6 10, ink at 10 %).
class OverPhotoButton extends StatelessWidget {
  const OverPhotoButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: Color(0x1A0F2145),
          blurRadius: 10,
          offset: Offset(0, 6),
        ),
      ],
    ),
    child: HubIconButton(
      icon: icon,
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      background: Colors.white,
    ),
  );
}

/// The wishlist heart over the photo: an outline heart, a filled orange one
/// once saved. A guest is asked to sign in.
class _HeartButton extends ConsumerWidget {
  const _HeartButton({required this.sku});

  final String sku;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final saved = ref.watch(
      wishlistControllerProvider.select((s) => s.contains(sku)),
    );
    Future<void> toggle() async {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await ref.read(wishlistControllerProvider.notifier).toggle(sku);
      if (!ok && context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.wishlistSignInPrompt)),
        );
      }
    }

    return OverPhotoButton(
      icon: saved ? Icons.favorite : HubIcons.heart,
      color: saved ? AppColors.accent : null,
      tooltip: l10n.navWishlist,
      onPressed: toggle,
    );
  }
}

/// Figma "pager": a white pill, 6 px dots 6 px apart, the current one a 16 px
/// navy capsule.
class _Pager extends StatelessWidget {
  const _Pager({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == index ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index
                  ? AppColors.brandPrimary
                  : AppColors.borderStrong,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ],
    ),
  );
}

/// Figma "counter": a navy pill with "1 / 4" in Caption Strong.
class _Counter extends StatelessWidget {
  const _Counter({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.brandPrimary,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '${index + 1} / $count',
      // Bare figures: the same order in Arabic.
      textDirection: TextDirection.ltr,
      style: AppTextStyles.of(context).captionStrong.copyWith(
        color: Colors.white,
      ),
    ),
  );
}

/// Small pill over a photo (Figma "Micro": 11 Bold, 8 × 4 padding, radius 6),
/// like the product card's NEW / discount badge.
class GalleryBadge extends StatelessWidget {
  const GalleryBadge({
    super.key,
    required this.label,
    required this.color,
    this.textColor = Colors.white,
    this.textDirection = TextDirection.ltr,
  });

  final String label;
  final Color color;
  final Color textColor;

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
      style: AppTextStyles.of(context).micro.copyWith(color: textColor),
    ),
  );
}
