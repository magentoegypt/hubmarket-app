import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/hm_link_navigation.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/category_icons.dart';
import '../../domain/hm_home.dart';

/// The storefront's pastel ramp for category chips (`_hm-figma.less`),
/// slots 0–7: mint, blue, amber, pink, lavender, cream, rose, indigo.
const List<Color> kCategoryTints = <Color>[
  Color(0xFFE8F5E9),
  Color(0xFFE3F2FD),
  Color(0xFFFFF3E0),
  Color(0xFFFCE4EC),
  Color(0xFFEDE7F6),
  Color(0xFFFFF8E1),
  Color(0xFFFDF5F9),
  Color(0xFFE8EAF6),
];

/// Shop by category (Figma 07 "carousel · category-rail"): 74×112 pastel
/// tiles with the admin's glyph, the category name and "N+ items".
class HmCategoryChips extends ConsumerWidget {
  const HmCategoryChips({super.key, required this.chips});

  final List<HmCategoryChip> chips;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _ChipTile(
          chip: chips[i],
          tint: kCategoryTints[(chips[i].tint ?? i) % kCategoryTints.length],
          onTap: () =>
              openHmLink(context, ref, chips[i].link, title: chips[i].name),
        ),
      ),
    );
  }
}

class _ChipTile extends StatelessWidget {
  const _ChipTile({required this.chip, required this.tint, this.onTap});

  final HmCategoryChip chip;
  final Color tint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final icon = chip.icon;
    return SizedBox(
      width: 74,
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Column(
              children: [
                SizedBox(
                  height: 28,
                  child: Center(
                    child: icon != null
                        ? Text(
                            icon,
                            style: const TextStyle(fontSize: 24, height: 1),
                          )
                        : Icon(
                            categoryIcon(chip.urlKey, chip.name),
                            size: 24,
                            color: AppColors.brandPrimary,
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  chip.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.captionStrong.copyWith(color: AppColors.inkHeading),
                ),
                const SizedBox(height: 4),
                if (chip.productCount > 0)
                  Text(
                    l10n.searchCategoryItems(chip.productCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.micro.copyWith(color: AppColors.inkMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
