import 'package:flutter/material.dart';

import '../../../../core/widgets/shimmer.dart';
import '../../../catalog/presentation/widgets/product_skeletons.dart';

/// The Home while its content is on its way (Figma S4 "Loading"): a hero block,
/// a row of category circles with their captions, a section title and two
/// product cards, all in the skeleton fill under a single shimmer. The header
/// above it is the real one (logo, search, delivery area): none of that waits
/// for the store.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  /// The frame's gutter, and the space between its blocks.
  static const double _gutter = 16;
  static const double _gap = 18;

  /// Five 64 px circles 12 px apart: the row runs 10 px into the gutter, as it
  /// does in the frame.
  static const double _circle = 64;
  static const int _circles = 5;
  static const double _circleGap = 12;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.all(_gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(height: 168, borderRadius: 16),
            const SizedBox(height: _gap),
            SizedBox(
              height: _circle + 6 + 10,
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth:
                    _circles * _circle + (_circles - 1) * _circleGap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < _circles; i++) ...[
                      if (i > 0) const SizedBox(width: _circleGap),
                      const _CategoryBlock(),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: _gap),
            const SkeletonBox(width: 140, height: 18, borderRadius: 8),
            const SizedBox(height: _gap),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ProductCardSkeletonShape()),
                SizedBox(width: 16),
                Expanded(child: ProductCardSkeletonShape()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A category circle and the bar for its name under it.
class _CategoryBlock extends StatelessWidget {
  const _CategoryBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonBox.circle(size: HomeSkeleton._circle),
        SizedBox(height: 6),
        SkeletonBox(width: 50, height: 10, borderRadius: 8),
      ],
    );
  }
}
