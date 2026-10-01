import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../domain/product_preview.dart';
import '../product_navigation.dart';
import 'product_card.dart';

/// A loading placeholder shaped like [ProductCard]: a square image block, then
/// the seller, name, rating and price + "+" rows as grey bars (the [Shimmer]
/// runs over the whole card, which has no surface of its own).
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: AspectRatio(
              aspectRatio: 1,
              child: SkeletonBox(borderRadius: 12),
            ),
          ),
          SizedBox(height: ProductCardMetrics.imageGap),
          // Seller, name, rating.
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 0.35,
            child: SkeletonBox(height: 12, borderRadius: 4),
          ),
          SizedBox(height: 8),
          SkeletonBox(height: 14, borderRadius: 4),
          SizedBox(height: 10),
          FractionallySizedBox(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 0.4,
            child: SkeletonBox(height: 12, borderRadius: 4),
          ),
          SizedBox(height: 10),
          // Price and the round add button.
          Row(
            children: [
              Expanded(
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: 0.6,
                  child: SkeletonBox(height: 16, borderRadius: 4),
                ),
              ),
              SkeletonBox(
                width: ProductCardMetrics.buttonSize,
                height: ProductCardMetrics.buttonSize,
                borderRadius: 18,
              ),
            ],
          ),
        ],
      ),
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
