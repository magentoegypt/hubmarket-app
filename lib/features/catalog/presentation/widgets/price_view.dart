import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/product.dart';

/// Stacked price (Figma "price-col"): the final price in EN/Price (15 Bold) over
/// the regular price in Caption (12), muted and struck through, when the
/// product is on sale. The final price turns `price/sale` orange then and is
/// ink otherwise.
class PriceView extends StatelessWidget {
  const PriceView({super.key, required this.product, this.alignEnd = false});

  final Product product;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final regular = product.regularPrice;
    final effective = product.finalPrice ?? regular;
    if (effective == null) return const SizedBox.shrink();
    final t = AppTextStyles.of(context);
    final onSale = product.isOnSale && regular != null;

    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          effective.formatted(),
          // Keep the "AED 1,234" token LTR even inside an RTL paragraph.
          textDirection: TextDirection.ltr,
          style: t.price.copyWith(
            color: onSale ? AppColors.accentStrong : AppColors.inkHeading,
          ),
        ),
        if (onSale)
          Text(
            regular.formatted(),
            textDirection: TextDirection.ltr,
            style: t.caption.copyWith(
              decoration: TextDecoration.lineThrough,
              color: AppColors.inkMuted,
            ),
          ),
      ],
    );
  }
}
