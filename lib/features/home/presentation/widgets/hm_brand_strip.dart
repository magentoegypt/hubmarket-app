import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../catalog/domain/brand.dart';

/// Top Brands (Figma 07 "carousel · brands"): 96×64 logo tiles; a tap opens
/// the brand's page (10e).
class HmBrandStrip extends StatelessWidget {
  const HmBrandStrip({super.key, required this.brands});

  final List<Brand> brands;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: brands.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _BrandTile(brand: brands[i]),
      ),
    );
  }
}

class _BrandTile extends StatelessWidget {
  const _BrandTile({required this.brand});

  final Brand brand;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    Widget name(BuildContext context) => Center(
      child: Text(
        brand.title,
        maxLines: 2,
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        style: t.captionStrong.copyWith(color: AppColors.inkHeading),
      ),
    );
    return SizedBox(
      width: 96,
      child: Semantics(
        button: true,
        label: brand.title,
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppColors.borderSubtle),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(
              AppRoutes.brandPage(brand.urlKey),
              extra: brand,
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: brand.imageUrl.isEmpty
                  ? name(context)
                  : HubImage(
                      url: brand.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (_) => const SizedBox.shrink(),
                      error: name,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
