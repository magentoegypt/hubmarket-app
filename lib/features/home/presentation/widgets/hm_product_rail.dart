import 'package:flutter/material.dart';

import '../../../catalog/domain/product.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/widgets/product_card.dart';

/// Home carousel card width (Figma 07): 152 pt, so the next card peeks.
const double kHmCardWidth = 152;

/// A horizontal product rail of Home cards. [ranked] marks them #1, #2, …
/// (Best sellers).
class HmProductRail extends StatelessWidget {
  const HmProductRail({super.key, required this.products, this.ranked = false});

  final List<Product> products;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: ProductCardMetrics.heightFor(context, kHmCardWidth),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: kHmCardWidth,
          child: ProductCard(
            product: products[i],
            rank: ranked ? i + 1 : null,
            onTap: () => openProduct(context, products[i]),
          ),
        ),
      ),
    );
  }
}
