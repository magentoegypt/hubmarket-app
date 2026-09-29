import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../domain/product_preview.dart';
import '../product_navigation.dart';

/// A loading placeholder shaped like [ProductCard]: a white bordered card with a
/// full-bleed image block on top and a name + price panel below. The white card
/// surface stays white — only the inner grey blocks shimmer (the [Shimmer] sits
/// inside the card, not over it).
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area — clipped to the card's rounded corners.
            Expanded(child: SkeletonBox(borderRadius: 0)),
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Two name lines (second shorter) + a price line.
                  SkeletonBox(height: 11, borderRadius: 4),
                  SizedBox(height: 6),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.7,
                    child: SkeletonBox(height: 11, borderRadius: 4),
                  ),
                  SizedBox(height: 10),
                  FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 0.45,
                    child: SkeletonBox(height: 13, borderRadius: 4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A non-scrolling 2-column grid of [ProductCardSkeleton]s, mirroring the real
/// product grids. [childAspectRatio] matches the screen it stands in for
/// (PLP `0.66`, Home rails `0.58`).
class ProductGridSkeleton extends StatelessWidget {
  const ProductGridSkeleton({
    super.key,
    required this.childAspectRatio,
    this.count = 6,
    this.padding = const EdgeInsets.all(16),
  });

  final double childAspectRatio;
  final int count;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: childAspectRatio,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: count,
      itemBuilder: (_, __) => const ProductCardSkeleton(),
    );
  }
}

/// The PDP's loading state, shaped like its content: a square gallery, then the
/// title/price block and the bars standing in for options, quantity and tabs.
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
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: (p != null && p.hasImage)
              ? HubImage(url: p.imageUrl, decodeWidth: pdpImageWidth(context))
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
                  style: const TextStyle(color: AppColors.inkMuted),
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
                Text(p.name!, style: Theme.of(context).textTheme.headlineSmall)
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPrimary,
                    fontSize: 20,
                  ),
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
