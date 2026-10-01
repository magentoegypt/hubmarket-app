import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/hm_link_navigation.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../../home/domain/hm_home.dart';
import '../../../home/presentation/hm_home_providers.dart';
import '../../domain/category.dart';
import '../category_icons.dart';
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
    final tiles = _popularTiles(context, ref);

    final sections = <List<Widget>>[
      if (recent.isNotEmpty)
        [
          _SectionTitle(
            title: l10n.searchRecentTitle,
            actionLabel: l10n.searchClearHistory,
            onAction: () => ref.read(searchHistoryProvider.notifier).clear(),
          ),
          const SizedBox(height: 14),
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
      if (tiles.isNotEmpty)
        [
          _SectionTitle(title: l10n.searchPopularCategories),
          const SizedBox(height: 14),
          SizedBox(
            height: _CategoryTile.height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: tiles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _CategoryTile(tile: tiles[i]),
            ),
          ),
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

  /// The tiles of Popular categories: Home's "Shop by category" chips as the
  /// admin set them up (their glyph, pastel and order — the same tile, the
  /// same colours), else the store's top-level categories that hold products.
  List<_Tile> _popularTiles(BuildContext context, WidgetRef ref) {
    final home = ref.watch(hmHomeProvider).valueOrNull;
    final chips = home == null ? null : _categoryChips(home);
    if (chips != null) {
      return [
        for (final chip in chips.take(popularLimit))
          _Tile(
            name: chip.name,
            urlKey: chip.urlKey,
            count: chip.productCount,
            glyph: chip.icon,
            tint: chip.tint,
            onTap: () =>
                openHmLink(context, ref, chip.link, title: chip.name),
          ),
      ];
    }
    final categories =
        ref.watch(searchCategoryChoicesProvider).valueOrNull ??
        const <Category>[];
    final shown = categories.take(popularLimit).toList(growable: false);
    return [
      for (var i = 0; i < shown.length; i++)
        _Tile(
          name: shown[i].name,
          urlKey: shown[i].urlKey,
          count: shown[i].productCount,
          // Without the admin's slots, the pastels run in order.
          tint: i,
          onTap: () => context.push(
            AppRoutes.category(shown[i].uid),
            extra: shown[i].name,
          ),
        ),
    ];
  }

  /// The first Shop by category section the admin shows, or null.
  static List<HmCategoryChip>? _categoryChips(HmHome home) {
    for (final section in home.visibleSections(DateTime.now())) {
      if (section.type == HmSectionType.categoryChips &&
          section.categories.isNotEmpty) {
        return section.categories;
      }
    }
    return null;
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
    final t = AppTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: SearchStyle.sectionTitle(context)),
          ),
          // A text link as tall as the title's line (the frame's row is 24).
          if (label != null)
            InkWell(
              onTap: onAction,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  label,
                  style: t.bodyStrong.copyWith(color: AppColors.accentStrong),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One recent search: clock · term · remove (x). Tapping the row searches it
/// again; the remove target is the row's full height at its end.
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
    final t = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(HubIcons.clock, size: 18, color: context.scaffoldMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    term,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(color: context.scaffoldHeading),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(HubIcons.x, size: 16, color: context.scaffoldMuted),
              ],
            ),
          ),
          PositionedDirectional(
            end: 0,
            top: 0,
            bottom: 0,
            width: 48,
            child: Semantics(
              button: true,
              label: l10n.searchRemoveRecent,
              excludeSemantics: true,
              child: Tooltip(
                message: l10n.searchRemoveRecent,
                child: InkResponse(onTap: onRemove, radius: 24),
              ),
            ),
          ),
        ],
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
    final t = AppTextStyles.of(context);
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
                style: t.captionStrong.copyWith(color: AppColors.accentStrong),
              ),
              const SizedBox(width: 6),
              Text(
                term,
                style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a Popular categories tile shows and opens.
class _Tile {
  const _Tile({
    required this.name,
    required this.urlKey,
    required this.count,
    required this.onTap,
    this.glyph,
    this.tint,
  });

  final String name;
  final String urlKey;
  final int count;

  /// The admin's glyph (an emoji); null draws the category's own icon.
  final String? glyph;

  /// The pastel slot (0–7) the admin gave the category; null takes the one
  /// the name's position picks.
  final int? tint;
  final VoidCallback onTap;
}

/// A 74 × 112 pastel tile (Figma "Category tile"): glyph, name, "7+ items".
/// The tile is a light surface in both themes, so its text keeps the fixed
/// ink tokens.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.tile});

  final _Tile tile;

  static const double width = 74;
  static const double height = 112;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final glyph = tile.glyph;
    final tints = SearchStyle.categoryTints;
    return SizedBox(
      width: width,
      child: Material(
        color: tints[(tile.tint ?? 0) % tints.length],
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tile.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 10),
            child: Column(
              children: [
                SizedBox(
                  height: 28,
                  child: Center(
                    child: glyph != null
                        ? Text(glyph, style: const TextStyle(fontSize: 24, height: 1))
                        : Icon(
                            categoryIcon(tile.urlKey, tile.name),
                            size: 24,
                            color: AppColors.brandPrimary,
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tile.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: t.captionStrong.copyWith(color: AppColors.inkHeading),
                ),
                const SizedBox(height: 4),
                if (tile.count > 0)
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      l10n.searchCategoryItems(tile.count),
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
