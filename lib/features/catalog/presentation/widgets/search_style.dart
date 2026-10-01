import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';

/// Figma values the search screens (09 · 09b · 09c · S2) use that the app theme
/// does not carry as tokens yet.
abstract final class SearchStyle {
  /// `border/strong` (#CBD3E2): outlined chips, the idle results field and the
  /// clear button.
  static const Color outline = Color(0xFFCBD3E2);

  /// Algolia's brand blue, for the "Search by algolia" attribution only.
  static const Color algoliaBlue = Color(0xFF003DFF);

  /// The storefront's category-chip pastels (`@hm-chip-tints` in the theme's
  /// `_hm-figma.less`), in order. The Figma tiles use the same eight.
  static const List<Color> categoryTints = <Color>[
    Color(0xFFE8F5E9),
    Color(0xFFE3F2FD),
    Color(0xFFFFF3E0),
    Color(0xFFFCE4EC),
    Color(0xFFEDE7F6),
    Color(0xFFFFF8E1),
    Color(0xFFFDF5F9),
    Color(0xFFE8EAF6),
  ];

  /// Section titles on the landing: "Heading 2" (18 bold).
  static TextStyle sectionTitle(BuildContext context) => AppTextStyles.of(
    context,
  ).heading2.copyWith(color: context.scaffoldHeading);

  /// Fill of the grey pills (trending searches) — `bg/subtle` on white.
  static Color pillFill(BuildContext context) =>
      context.isDarkMode ? Colors.white10 : AppColors.surfaceSubtle;

  /// Border of the outlined chips.
  static Color chipBorder(BuildContext context) =>
      context.isDarkMode ? Colors.white24 : outline;
}

/// Wraps what the shopper typed in Unicode first-strong isolates before it goes
/// into a sentence, so a Latin query inside Arabic copy ("لا توجد نتائج لـ
/// «samsung tv»") keeps its words and quotes in order instead of being
/// reshuffled by the surrounding right-to-left text.
String isolateQuery(String query) => '\u2068$query\u2069';

/// A 36 pt outlined pill (Figma "Chip"): the type-ahead's category chips.
class SearchOutlinedChip extends StatelessWidget {
  const SearchOutlinedChip({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(color: SearchStyle.chipBorder(context)),
    );
    return Material(
      color: context.isDarkMode ? Colors.transparent : Colors.white,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
        ),
      ),
    );
  }
}

/// "Search by algolia" (Figma 09). The type-ahead shows it only when Algolia
/// answered — the app queries the storefront's Algolia indices directly — and
/// hides it on the GraphQL fallback. A brand lockup, so it stays in English
/// and left-to-right in both languages, as the AR frame draws it.
class SearchByAlgolia extends StatelessWidget {
  const SearchByAlgolia({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Search by Algolia',
      child: ExcludeSemantics(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Search by ',
                  style: TextStyle(fontSize: 11, color: context.scaffoldMuted),
                ),
                const TextSpan(
                  text: 'algolia',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SearchStyle.algoliaBlue,
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
