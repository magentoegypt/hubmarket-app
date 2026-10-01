import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/category.dart';
import '../catalog_providers.dart';
import '../search_history.dart';
import '../search_providers.dart';
import 'search_style.dart';
import '../../../../app/theme/hub_icons.dart';

/// The search landing, before anything is typed (Figma 09b): recent searches
/// with a per-row remove, the numbered trending searches, and a carousel of
/// popular categories. Every section with nothing to show collapses.
class SearchLanding extends ConsumerWidget {
  const SearchLanding({super.key, required this.onPick});

  /// Runs a search for a recent or trending term.
  final ValueChanged<String> onPick;

  /// Rows the Recent section shows (history keeps a few more).
  static const int recentLimit = 5;

  /// Tiles in Popular categories — the storefront's category chips cap at 8.
  static const int popularLimit = 8;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final history = ref.watch(searchHistoryProvider);
    final recent = history.take(recentLimit).toList(growable: false);
    // Only the admin's list (Hub Market App settings): without one — Build 1
    // or none configured — the section hides. The app never invents trends.
    final trending = ref.watch(trendingSearchesProvider);
    final categories =
        ref.watch(searchCategoryChoicesProvider).valueOrNull ??
        const <Category>[];

    final sections = <List<Widget>>[
      if (recent.isNotEmpty)
        [
          _SectionTitle(
            title: l10n.searchRecentTitle,
            actionLabel: l10n.searchClearHistory,
            onAction: () => ref.read(searchHistoryProvider.notifier).clear(),
          ),
          // 14 in the frame, less the Clear button's taller tap target.
          const SizedBox(height: 10),
          for (final term in recent)
            _RecentRow(
              term: term,
              onTap: () => onPick(term),
              onRemove: () =>
                  ref.read(searchHistoryProvider.notifier).remove(term),
            ),
        ],
      if (trending.isNotEmpty)
        [
          _SectionTitle(title: l10n.searchTrendingTitle),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < trending.length; i++)
                  _TrendingPill(
                    rank: i + 1,
                    term: trending[i],
                    onTap: () => onPick(trending[i]),
                  ),
              ],
            ),
          ),
        ],
      if (categories.isNotEmpty)
        [
          _SectionTitle(title: l10n.searchPopularCategories),
          const SizedBox(height: 14),
          _PopularCategories(categories: categories),
        ],
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(height: 14),
            Container(height: 8, color: context.sectionBand),
            const SizedBox(height: 14),
          ],
          ...sections[i],
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: SearchStyle.sectionTitle(context)),
          ),
          if (label != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accentStrong,
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 32),
                alignment: AlignmentDirectional.centerEnd,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              // On the Text: a ButtonStyle textStyle would drop the theme font.
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One recent search: clock · term · remove (x). Tapping the row searches it
/// again.
class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.term,
    required this.onTap,
    required this.onRemove,
  });

  final String term;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        // 8 at the end: the remove button's 32 pt target puts its 16 pt glyph
        // 16 from the edge, as drawn.
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 4),
        child: Row(
          children: [
            Icon(HubIcons.clock, size: 18, color: context.scaffoldMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                term,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  color: context.scaffoldHeading,
                ),
              ),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: l10n.searchRemoveRecent,
              iconSize: 16,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              color: context.scaffoldMuted,
              icon: const Icon(HubIcons.x),
            ),
          ],
        ),
      ),
    );
  }
}

/// A numbered grey pill: "1 bag".
class _TrendingPill extends StatelessWidget {
  const _TrendingPill({
    required this.rank,
    required this.term,
    required this.onTap,
  });

  final int rank;
  final String term;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: SearchStyle.pillFill(context),
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentStrong,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                term,
                style: TextStyle(
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600,
                  color: context.scaffoldHeading,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Popular categories: pastel tiles, each opening the category's listing.
class _PopularCategories extends ConsumerWidget {
  const _PopularCategories({required this.categories});

  /// Every top-level category with products. Only the first
  /// [SearchLanding.popularLimit] are drawn, but the stand-in thumbnail lookup
  /// is keyed on the whole list — the key Home's Shop by category already
  /// fetched, so this normally costs no request.
  final List<Category> categories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnails =
        ref
            .watch(categoryThumbnailsProvider(categoryThumbnailKey(categories)))
            .valueOrNull ??
        const <String, String>{};
    final shown = categories
        .take(SearchLanding.popularLimit)
        .toList(growable: false);
    return SizedBox(
      height: _CategoryTile.height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: shown.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final category = shown[i];
          final image = category.image ?? '';
          return _CategoryTile(
            category: category,
            imageUrl: image.isNotEmpty ? image : thumbnails[category.uid],
            tint:
                SearchStyle.categoryTints[i % SearchStyle.categoryTints.length],
          );
        },
      ),
    );
  }
}

/// A 74 × 112 pastel tile: image (or a glyph), name, "7+ items". The tile is a
/// light surface in both themes, so its text keeps the fixed ink tokens.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.imageUrl,
    required this.tint,
  });

  final Category category;
  final String? imageUrl;
  final Color tint;

  static const double width = 74;
  static const double height = 112;
  static const double _media = 36;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const glyph = Center(
      child: Icon(
        HubIcons.layoutGrid,
        size: 28,
        color: AppColors.brandPrimary,
      ),
    );
    return SizedBox(
      width: width,
      child: Material(
        color: tint,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(
            AppRoutes.category(category.uid),
            extra: category.name,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Column(
              children: [
                SizedBox.square(
                  dimension: _media,
                  child: (imageUrl ?? '').isEmpty
                      ? glyph
                      : HubImage(
                          url: imageUrl,
                          width: _media,
                          height: _media,
                          borderRadius: BorderRadius.circular(8),
                          placeholder: (_) => glyph,
                          error: (_) => glyph,
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  category.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkHeading,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    l10n.searchCategoryItems(category.productCount),
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMuted,
                    ),
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
