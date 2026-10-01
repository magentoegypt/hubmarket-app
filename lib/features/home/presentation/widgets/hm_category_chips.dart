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
      height: HmCategoryTile.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => HmCategoryTile(
          name: chips[i].name,
          tint: kCategoryTints[(chips[i].tint ?? i) % kCategoryTints.length],
          emoji: chips[i].icon,
          icon: categoryIcon(chips[i].urlKey, chips[i].name),
          count: chips[i].productCount,
          onTap: () =>
              openHmLink(context, ref, chips[i].link, title: chips[i].name),
        ),
      ),
    );
  }
}

/// A category tile (Figma "Category tile"): 74×112, radius 16, on its [tint];
/// the 28 pt glyph — the admin's [emoji], else the category's Lucide [icon] —
/// the name (Caption Strong, up to two lines) and "N+ items" (Micro, muted).
class HmCategoryTile extends StatelessWidget {
  const HmCategoryTile({
    super.key,
    required this.name,
    required this.tint,
    required this.icon,
    this.emoji,
    this.count = 0,
    this.onTap,
  });

  static const double width = 74;
  static const double height = 112;

  final String name;
  final Color tint;
  final IconData icon;

  /// Drawn instead of [icon] when set.
  final String? emoji;

  /// The number of products; the line is left out for none.
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final glyph = emoji;
    return SizedBox(
      width: width,
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
                    child: glyph != null
                        ? Text(glyph, style: const TextStyle(fontSize: 24, height: 1))
                        : Icon(icon, size: 24, color: AppColors.brandPrimary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.captionStrong.copyWith(color: AppColors.inkHeading),
                ),
                const SizedBox(height: 4),
                // One line: a longer count ("أكثر من 19 منتج") shrinks to fit
                // the tile instead of being cut.
                if (count > 0)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.searchCategoryItems(count),
                      maxLines: 1,
                      style: t.micro.copyWith(color: AppColors.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
