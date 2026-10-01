import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../domain/product_preview.dart';
import '../product_navigation.dart';
import 'product_card.dart';
import 'product_gallery.dart';

/// A loading placeholder for [ProductCard] (Figma S4 "card-skeleton"): a square
/// image block, then four bars 8 px apart — the seller, the name on two lines
/// and the price (the [Shimmer] runs over the whole card, which has no surface
/// of its own).
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) =>
      const Shimmer(child: ProductCardSkeletonShape());
}

/// What [ProductCardSkeleton] draws, without a [Shimmer] of its own: for a
/// skeleton page that runs one shimmer over everything. The bars are the
/// frame's 60, 150, 110 and 70 px under a 171 px card, as shares of the width.
class ProductCardSkeletonShape extends StatelessWidget {
  const ProductCardSkeletonShape({super.key});

  static Widget _bar(double share, double height) => FractionallySizedBox(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: share,
    child: SkeletonBox(height: height, borderRadius: 8),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Flexible(
          child: AspectRatio(
            aspectRatio: 1,
            child: SkeletonBox(borderRadius: 12),
          ),
        ),
        const SizedBox(height: 8),
        _bar(60 / 171, 10),
        const SizedBox(height: 8),
        _bar(150 / 171, 12),
        const SizedBox(height: 8),
        _bar(110 / 171, 12),
        const SizedBox(height: 8),
        _bar(70 / 171, 16),
      ],
    );
  }
}

/// A non-scrolling 2-column grid of [ProductCardSkeleton]s, laid out exactly
/// like the real product grids ([productGridDelegate]).
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({
    super.key,
    this.count = 6,
    this.padding = const EdgeInsets.all(16),
  });

  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: productGridDelegate(context),
      itemCount: count,
      itemBuilder: (_, __) => const ProductCardSkeleton(),
    );
  }
}

/// The PDP's loading state, shaped like its content: the 400 px photo stage, then
/// the title/price block and the bars standing in for the options and the
/// sections after them.
///
/// When [preview] is present (the user tapped a listing card) the hero image,
/// brand, name and price are the *real* ones and paint in the first frame —
/// the shimmer is left only for what the listing genuinely did not know. The
/// listing price is a `price_range` minimum and can differ from the selected
/// variant's, so it is shown here and nowhere else; the loaded PDP always
/// prices from its own document.
class ProductDetailSkeleton extends StatelessWidget {
  const ProductDetailSkeleton({super.key, this.preview});

  final ProductPreview? preview;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final price = p?.finalPrice ?? p?.regularPrice;
    final t = AppTextStyles.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // The photo stage of Figma 14: 400 high on `bg/muted`, the photo
        // contained in it.
        SizedBox(
          height: ProductGallery.defaultHeight,
          child: (p != null && p.hasImage)
              ? ColoredBox(
                  color: AppColors.surfaceSubtle,
                  child: HubImage(
                    url: p.imageUrl,
                    fit: BoxFit.contain,
                    decodeWidth: pdpImageWidth(context),
                  ),
                )
              : const Shimmer(child: SkeletonBox(borderRadius: 0)),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p?.brand != null && p!.brand!.isNotEmpty)
                Text(
                  p.brand!,
                  style: t.captionStrong.copyWith(color: AppColors.brandPrimary),
                )
              else
                const Shimmer(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.3,
                    child: SkeletonBox(height: 12, borderRadius: 4),
                  ),
                ),
              const SizedBox(height: 8),
              if (p?.name != null && p!.name!.isNotEmpty)
                Text(
                  p.name!,
                  style: t.heading1.copyWith(color: AppColors.inkHeading),
                )
              else
                const Shimmer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBox(height: 18, borderRadius: 4),
                      SizedBox(height: 8),
                      FractionallySizedBox(
                        alignment: AlignmentDirectional.centerStart,
                        widthFactor: 0.6,
                        child: SkeletonBox(height: 18, borderRadius: 4),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (price != null)
                Text(
                  price.formatted(),
                  // Keep the "AED 1,234.00" token LTR inside an RTL paragraph.
                  textDirection: TextDirection.ltr,
                  style: t.priceLarge.copyWith(color: AppColors.inkHeading),
                )
              else
                const Shimmer(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.35,
                    child: SkeletonBox(height: 20, borderRadius: 4),
                  ),
                ),
              const SizedBox(height: 24),
              // Options / quantity / tabs — never known from a listing.
              const Shimmer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: 0.5,
                      child: SkeletonBox(height: 14, borderRadius: 4),
                    ),
                    SizedBox(height: 16),
                    SkeletonBox(height: 44, borderRadius: 8),
                    SizedBox(height: 20),
                    SkeletonBox(height: 14, borderRadius: 4),
                    SizedBox(height: 10),
                    SkeletonBox(height: 14, borderRadius: 4),
                    SizedBox(height: 10),
                    FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: 0.8,
                      child: SkeletonBox(height: 14, borderRadius: 4),
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
