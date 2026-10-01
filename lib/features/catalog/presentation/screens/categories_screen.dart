import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../l10n/l10n.dart';
import '../../../stores/domain/store.dart';
import '../../../stores/presentation/stores_providers.dart';
import '../../../stores/presentation/widgets/store_widgets.dart';
import '../../domain/category.dart';
import '../category_icons.dart';
import '../category_stores.dart';
import '../catalog_providers.dart';

/// Categories tab (Figma 08): a rail of the top-level categories on the
/// start side, and for the one picked a banner, "Shop by type" tiles for its
/// sub-categories and — with the Hub Market App's seller API — "Top stores in
/// …". The rail ends with Bundle Deals where the app has them.
///
/// Tiles lead to a listing; the banner leads to the picked category's own.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  /// The category the panel shows; the first one until the shopper picks.
  String? _selectedUid;
  final ScrollController _panelScroll = ScrollController();

  @override
  void dispose() {
    _panelScroll.dispose();
    super.dispose();
  }

  void _select(Category category) {
    if (category.uid == _selectedUid) return;
    setState(() => _selectedUid = category.uid);
    if (_panelScroll.hasClients) _panelScroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoryTreeProvider);
    final bundles = ref.watch(storesAvailableProvider);

    return HubScaffold(
      currentTab: AppTab.categories,
      appBar: _RuledBar(
        bar: HubTopBar(
          title: l10n.navCategories,
          showBack: false,
          actions: [
            HubIconButton(
              icon: HubIcons.search,
              tooltip: l10n.searchHint,
              onPressed: () => context.push(AppRoutes.search),
            ),
          ],
        ),
      ),
      body: AsyncValueView(
        value: categories,
        onRetry: () => ref.invalidate(categoryTreeProvider),
        loading: () => const _CategoriesSkeleton(),
        data: (items) {
          final menu = [
            for (final c in items)
              if (c.includeInMenu && c.name.isNotEmpty) c,
          ];
          if (menu.isEmpty) {
            return Center(child: Text(l10n.stateEmpty));
          }
          final selected = menu.firstWhere(
            (c) => c.uid == _selectedUid,
            orElse: () => menu.first,
          );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _CategoryRail.width,
                child: _CategoryRail(
                  items: menu,
                  selectedUid: selected.uid,
                  onSelect: _select,
                  // Bundle Deals is the Hub Market App's list.
                  onBundles: bundles
                      ? () => context.push(AppRoutes.bundles)
                      : null,
                ),
              ),
              Expanded(
                child: _CategoryPanel(
                  key: ValueKey(selected.uid),
                  category: selected,
                  controller: _panelScroll,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The page while the categories load: the rail's rows, the banner, the
/// tiles — in their places, shimmering.
class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width) => SkeletonBox(width: width, height: 12);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _CategoryRail.width,
          child: ColoredBox(
            color: AppColors.surfaceSubtle,
            // Darker than the page's blocks: they sit on the rail's grey.
            child: Shimmer(
              base: AppColors.borderSubtle,
              child: Column(
                children: [
                  for (var i = 0; i < 8; i++)
                    SizedBox(
                      height: 48,
                      child: Center(child: bar(i.isEven ? 56 : 44)),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: Shimmer(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(height: 96, borderRadius: 12),
                  const SizedBox(height: 14),
                  const SkeletonBox(width: 110, height: 16),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      for (var i = 0; i < 6; i++)
                        const SizedBox(
                          width: TypeTile.size,
                          child: Column(
                            children: [
                              SkeletonBox(
                                width: TypeTile.size,
                                height: TypeTile.size,
                                borderRadius: 14,
                              ),
                              SizedBox(height: 6),
                              SkeletonBox(width: 56, height: 10),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The app bar with the frame's 1 pt rule along its foot (inside its 56 pt).
class _RuledBar extends StatelessWidget implements PreferredSizeWidget {
  const _RuledBar({required this.bar});

  final HubTopBar bar;

  @override
  Size get preferredSize => bar.preferredSize;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      bar,
      const PositionedDirectional(
        start: 0,
        end: 0,
        bottom: 0,
        child: ColoredBox(
          color: AppColors.borderSubtle,
          child: SizedBox(height: 1),
        ),
      ),
    ],
  );
}

/// The rail (Figma "category-list"): 104 pt wide on the `bg/subtle` ground.
/// The picked row is white with a 3 pt orange bar on its start edge.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({
    required this.items,
    required this.selectedUid,
    required this.onSelect,
    this.onBundles,
  });

  final List<Category> items;
  final String selectedUid;
  final ValueChanged<Category> onSelect;
  final VoidCallback? onBundles;

  static const double width = 104;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A Material, so the rows' ink shows over the ground.
    return Material(
      color: AppColors.surfaceSubtle,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          for (final category in items)
            _RailItem(
              label: category.name,
              selected: category.uid == selectedUid,
              onTap: () => onSelect(category),
            ),
          if (onBundles != null)
            _RailItem(
              label: l10n.bundlesTitle,
              selected: false,
              onTap: onBundles!,
            ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? Colors.white : null,
            border: selected
                ? const BorderDirectional(
                    start: BorderSide(color: AppColors.accent, width: 3),
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
          child: Center(
            child: SizedBox(
              width: 84,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: (selected ? t.captionStrong : t.caption).copyWith(
                  color: selected
                      ? AppColors.accentStrong
                      : AppColors.inkSubtle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What the rail's pick shows: the banner, the sub-category tiles and the
/// category's top stores.
class _CategoryPanel extends ConsumerWidget {
  const _CategoryPanel({
    super.key,
    required this.category,
    required this.controller,
  });

  final Category category;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);

    final subs = [
      for (final c in category.children)
        if (c.includeInMenu && c.name.isNotEmpty) c,
    ];
    // Sub-categories carry no photo on this store: a product of each stands
    // in, as the storefront does — and for the banner of a category without
    // a photo of its own.
    final thumbnails =
        ref
            .watch(
              categoryThumbnailsProvider(
                categoryThumbnailKey([
                  ...subs,
                  if ((category.image ?? '').isEmpty) category,
                ]),
              ),
            )
            .valueOrNull ??
        const <String, String>{};

    final storesOn = ref.watch(storesAvailableProvider);
    final categoryId = int.tryParse(categoryIdFromUid(category.uid) ?? '');
    final stores = storesOn && categoryId != null
        ? ref.watch(categoryStoresProvider(categoryId)).valueOrNull
        : null;
    final topStores = stores?.items ?? const <HmStoreCard>[];

    final counts = [
      if (category.productCount > 0)
        l10n.categoryProductCount(category.productCount),
      if (stores != null && stores.totalCount > 0)
        l10n.categoryStoreCount(stores.totalCount),
    ].join(' · ');

    final bannerImage = (category.image ?? '').isNotEmpty
        ? category.image
        : thumbnails[category.uid];

    return ListView(
      controller: controller,
      padding: const EdgeInsetsDirectional.fromSTEB(14, 16, 16, 16),
      children: [
        _Banner(
          key: const ValueKey('category-banner'),
          name: category.name,
          counts: counts,
          imageUrl: bannerImage,
          onTap: () => context.push(
            AppRoutes.category(category.uid),
            extra: category.name,
          ),
        ),
        if (subs.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            l10n.categoryShopByType,
            style: t.title.copyWith(color: AppColors.inkHeading),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 14,
            children: [
              for (final sub in subs)
                TypeTile(
                  category: sub,
                  imageUrl: (sub.image ?? '').isNotEmpty
                      ? sub.image
                      : thumbnails[sub.uid],
                ),
            ],
          ),
        ],
        if (topStores.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            l10n.categoryTopStores(category.name),
            style: t.title.copyWith(color: AppColors.inkHeading),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < topStores.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _StoreRow(store: topStores[i]),
          ],
        ],
      ],
    );
  }
}

/// The category banner (Figma "banner"): 96 pt tall, 12 pt corners, the photo
/// under a navy wash that fades out from the start edge, the name in Heading 1
/// and the counts under it. Opens the category's listing.
class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.name,
    required this.counts,
    required this.imageUrl,
    required this.onTap,
  });

  final String name;
  final String counts;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      label: name,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 96,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: AppColors.brandPrimary),
              if ((imageUrl ?? '').isNotEmpty)
                HubImage(
                  url: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (_) =>
                      const ColoredBox(color: AppColors.brandPrimary),
                  error: (_) => const ColoredBox(color: AppColors.brandPrimary),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [Color(0xCC0F2144), Color(0x000F2144)],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.heading1.copyWith(color: Colors.white),
                    ),
                    if (counts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        counts,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption.copyWith(
                          color: AppColors.borderStrong,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sub-category tile (Figma "sub/…"): a 74 pt rounded photo and its name in
/// up to two lines. Opens the category's listing.
class TypeTile extends StatelessWidget {
  const TypeTile({super.key, required this.category, required this.imageUrl});

  final Category category;

  /// The category's own photo, or the product stand-in the panel resolved;
  /// null shows the category's icon.
  final String? imageUrl;

  static const double size = 74;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final fallback = ColoredBox(
      color: AppColors.surfaceSubtle,
      child: Center(
        child: Icon(
          categoryIcon(category.urlKey, category.name),
          size: 28,
          color: AppColors.brandPrimary,
        ),
      ),
    );
    return SizedBox(
      width: size,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => openCategory(context, category),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox.square(
                dimension: size,
                child: (imageUrl ?? '').isEmpty
                    ? fallback
                    : HubImage(
                        url: imageUrl,
                        shimmer: true,
                        placeholder: (_) =>
                            const ColoredBox(color: AppColors.surfaceSubtle),
                        error: (_) => fallback,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Text(
                category.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a category's listing, which draws its own sub-category rail.
void openCategory(BuildContext context, Category category) =>
    context.push(AppRoutes.category(category.uid), extra: category.name);

/// One of the category's top stores (Figma "top-stores/row"): logo, name,
/// "★ 4.8 · 38 products" and a chevron. Opens the store.
class _StoreRow extends StatelessWidget {
  const _StoreRow({required this.store});

  final HmStoreCard store;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final shape = RoundedRectangleBorder(
      side: const BorderSide(color: AppColors.borderSubtle),
      borderRadius: BorderRadius.circular(12),
    );
    return Material(
      color: Colors.white,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openStore(context, store),
        customBorder: shape,
        child: Padding(
          // 10 inside the 1 pt outline.
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              StoreLogo(store: store, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (store.isRated) ...[
                            ratingSpan(
                              store.rating!,
                              size: 12,
                              color: AppColors.inkMuted,
                              starFirst: true,
                            ),
                            const TextSpan(text: ' · '),
                          ],
                          TextSpan(
                            text: l10n.categoryProductCount(store.productCount),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // chevron_right mirrors itself in RTL.
              const Icon(
                HubIcons.chevronRight,
                size: 18,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sub-category drill-down: the categories below one, as the same tiles.
///
/// The Categories tab no longer routes here (its panel shows the tiles and a
/// tile opens the listing, which draws its own sub-category rail); the route
/// stays for links that name one.
class SubcategoriesScreen extends ConsumerWidget {
  const SubcategoriesScreen({super.key, required this.categoryUid, this.title});

  final String categoryUid;
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final category = ref.watch(categoryByUidProvider(categoryUid));

    return HubScaffold(
      currentTab: AppTab.categories,
      appBar: HubTopBar(
        title: category.valueOrNull?.name ?? title ?? l10n.navCategories,
      ),
      body: AsyncValueView(
        value: category,
        onRetry: () => ref.invalidate(categoryTreeProvider),
        data: (cat) {
          final subs = [
            for (final c in cat?.children ?? const <Category>[])
              if (c.includeInMenu) c,
          ];
          if (subs.isEmpty) {
            return Center(child: Text(l10n.stateEmpty));
          }
          return _SubcategoryTiles(items: subs);
        },
      ),
    );
  }
}

class _SubcategoryTiles extends ConsumerWidget {
  const _SubcategoryTiles({required this.items});

  final List<Category> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnails =
        ref
            .watch(categoryThumbnailsProvider(categoryThumbnailKey(items)))
            .valueOrNull ??
        const <String, String>{};
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [
            for (final sub in items)
              TypeTile(
                category: sub,
                imageUrl: (sub.image ?? '').isNotEmpty
                    ? sub.image
                    : thumbnails[sub.uid],
              ),
          ],
        ),
      ],
    );
  }
}
