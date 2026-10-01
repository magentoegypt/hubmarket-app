import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/category.dart';
import '../catalog_providers.dart';
import '../../../../app/theme/hub_icons.dart';

/// Categories tab — heading + search box + a grid of category image cards
/// (photo, name, product count) per Figma.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoryTreeProvider);

    return HubScaffold(
      currentTab: AppTab.categories,
      // The page has its own search box, so drop the redundant app-bar search
      // icon (Figma).
      showSearch: false,
      body: AsyncValueView(
        value: categories,
        onRetry: () => ref.invalidate(categoryTreeProvider),
        data: (items) {
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
                child: Text(
                  l10n.navCategories,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                child: Text(
                  l10n.categoriesSubtitle,
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              ),
              // Tap-to-search box (the page has a search box per the design).
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(AppRoutes.search),
                  child: IgnorePointer(
                    child: TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        hintText: l10n.searchHint,
                        prefixIcon: const Icon(HubIcons.search),
                      ),
                    ),
                  ),
                ),
              ),
              // 8px section band separating the header from the grid (Figma 57:23).
              const SizedBox(
                height: 8,
                child: ColoredBox(color: AppColors.surfaceMuted),
              ),
              _CategoryGrid(items: items),
            ],
          );
        },
      ),
    );
  }
}

/// Sub-category drill-down: tapping a parent category lists its child
/// categories (which themselves drill down or open the PLP when they're leaves).
///
/// Reached from the Categories tab, which browses the tree rather than jumping
/// to products. Its tiles resolve artwork the same way the listing's rail does,
/// so a level whose categories carry no `image` still shows real imagery
/// (CL042-DEV22) instead of a wall of placeholders.
class SubcategoriesScreen extends ConsumerWidget {
  const SubcategoriesScreen({
    super.key,
    required this.categoryUid,
    this.title,
  });

  final String categoryUid;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final category = ref.watch(categoryByUidProvider(categoryUid));

    return HubScaffold(
      currentTab: AppTab.categories,
      body: AsyncValueView(
        value: category,
        onRetry: () => ref.invalidate(categoryTreeProvider),
        data: (cat) {
          final subs = (cat?.children ?? const <Category>[])
              .where((c) => c.includeInMenu)
              .toList(growable: false);
          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
                child: Text(
                  cat?.name ?? title ?? l10n.navCategories,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
                child: Text(
                  l10n.categoryCount(subs.length),
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              ),
              _CategoryGrid(items: subs),
            ],
          );
        },
      ),
    );
  }
}

/// Opens a tapped category: drills into the sub-category grid when it has
/// navigable children, otherwise jumps straight to its product listing.
///
/// This tab is the browse surface — its job is to open up the tree, so a parent
/// shows what's inside it rather than going straight to products. Home and the
/// drawer still go directly to the listing, which is the shortcut path. (The
/// two were briefly unified onto the listing; the grid is what's wanted here.)
void _openCategory(BuildContext context, Category category) {
  final hasSubcategories = category.children.any((c) => c.includeInMenu);
  context.push(
    hasSubcategories
        ? AppRoutes.subcategories(category.uid)
        : AppRoutes.category(category.uid),
    extra: category.name,
  );
}

/// Two-column grid of category cards, shared by the top-level Categories tab
/// and the sub-category drill-down.
///
/// Sub-categories carry no `image` on this store, which left the whole
/// drill-down as a wall of placeholders (CL042-DEV22). Resolve a stand-in from
/// the first product in each — the substitution the storefront makes — in a
/// single batched query for the whole grid.
class _CategoryGrid extends ConsumerWidget {
  const _CategoryGrid({required this.items});

  final List<Category> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final thumbnails =
        ref
            .watch(categoryThumbnailsProvider(categoryThumbnailKey(items)))
            .valueOrNull ??
        const <String, String>{};
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text(l10n.stateEmpty)),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        // Figma card ≈ 170×147 (photo 94 + label panel 53).
        childAspectRatio: 170 / 147,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final category = items[index];
        return _CategoryCard(
          category: category,
          imageUrl: (category.image ?? '').isNotEmpty
              ? category.image
              : thumbnails[category.uid],
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, this.imageUrl});

  final Category category;

  /// The category's own photo, or the product stand-in resolved by the grid.
  /// Null when neither exists — the card then shows the neutral placeholder
  /// rather than borrowing an unrelated image.
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _openCategory(context, category),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Full-bleed photo area (Figma 94px of a 147px card).
            Expanded(
              child: SizedBox(
                width: double.infinity,
                child: HubImage(
                  url: imageUrl,
                  shimmer: true,
                  error: (_) => const _CategoryPlaceholder(),
                ),
              ),
            ),
            // White label panel — name + product count.
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                      color: AppColors.inkHeading,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.categoryProductCount(category.productCount),
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pale navy chip with the neutral category glyph — the stand-in for a
/// category tile that has no photo (the beauty teardrop was Zoonze's).
class _CategoryPlaceholder extends StatelessWidget {
  const _CategoryPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppColors.surfaceTint,
      child: Center(
        child: Icon(HubIcons.layoutGrid, color: AppColors.brandPrimary),
      ),
    );
  }
}
