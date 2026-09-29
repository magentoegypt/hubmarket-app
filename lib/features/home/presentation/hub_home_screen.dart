import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/network_image.dart';
import '../../../core/widgets/shimmer.dart';
import '../../../l10n/l10n.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/product_navigation.dart';
import '../../catalog/presentation/storefront_links.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import '../../catalog/presentation/widgets/product_skeletons.dart';
import '../domain/home_content.dart';
import 'home_providers.dart';

/// Carousel card width (Figma v2/v3): 152 pt so the next card peeks ~30%.
const double _kCardWidth = 152;
const double _kRailHeight = 292;

/// Hub Market Home (Figma "07 Home", v3). Every section is fed by Magento:
/// categories and products from the catalogue, the promise strip, promo cards
/// and trust row from the storefront's own CMS blocks. A section whose source
/// is empty collapses — nothing is hard-coded or invented.
class HubHomeScreen extends ConsumerWidget {
  const HubHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return HubScaffold(
      currentTab: AppTab.home,
      showSearch: false,
      appBar: const _HomeHeader(),
      body: RefreshIndicator(
        color: AppColors.brandPrimary,
        onRefresh: () async {
          ref
            ..invalidate(homeCmsBlocksProvider)
            ..invalidate(categoryTreeProvider)
            ..invalidate(homeDealsProvider)
            ..invalidate(homeCategoryRailProvider);
          try {
            await ref.read(homeCategoriesProvider.future);
          } catch (_) {
            // A failed feed collapses its own section; nothing to surface here.
          }
        },
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: const [
            _PromiseStrip(),
            _ShopByCategory(),
            _TodaysDeals(),
            _CategoryRails(),
            _PromoBanners(),
            _TrustRow(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── header

class _HomeHeader extends StatelessWidget implements PreferredSizeWidget {
  const _HomeHeader();

  static const double _contentHeight = 4 + 48 + 8 + 46 + 10 + 20 + 12;

  @override
  Size get preferredSize {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final top = view.viewPadding.top / view.devicePixelRatio;
    return Size.fromHeight(top + _contentHeight);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      color: AppColors.brandPrimary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    const BrandLogo(height: 34, onDark: true),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.notificationsTitle,
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => context.push(AppRoutes.notifications),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _SearchBox(
                  hint: l10n.homeSearchMarketplaceHint,
                  onTap: () => context.push(AppRoutes.search),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 20,
                child: InkWell(
                  onTap: () => context.push(AppRoutes.addresses),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.accent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.homeDeliverTo,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.homeChooseArea,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Icon(Icons.expand_more, size: 16, color: Colors.white),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hint,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 14),
                  child: Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.inkMuted, fontSize: 14),
                  ),
                ),
              ),
              Container(
                width: 50,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadiusDirectional.horizontal(
                    end: Radius.circular(12),
                  ),
                ),
                child: const Icon(Icons.search, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── strip

class _PromiseStrip extends ConsumerWidget {
  const _PromiseStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = ref.watch(homePromiseProvider);
    if (text.isEmpty) return const SizedBox(height: 8);
    return Container(
      color: const Color(0xFFFFF4EC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.local_shipping_outlined, size: 16, color: AppColors.accentStrong),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.accentStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── sections

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTheme.displayFont,
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: AppColors.inkHeading,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: AppColors.accentStrong),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ShopByCategory extends ConsumerWidget {
  const _ShopByCategory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(homeCategoriesProvider);
    return categories.when(
      loading: () => const _CategorySkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final thumbs = ref
                .watch(categoryThumbnailsProvider(categoryThumbnailKey(items)))
                .valueOrNull ??
            const <String, String>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: l10n.homeShopByCategory,
              actionLabel: l10n.homeSeeAll,
              onAction: () => context.go(AppRoutes.categories),
            ),
            SizedBox(
              height: 124,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) => _CategoryTile(
                  category: items[i],
                  imageUrl: items[i].image ?? thumbs[items[i].uid],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.imageUrl});

  final Category category;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 74,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(AppRoutes.category(category.uid)),
        child: Column(
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.surfaceTint,
                borderRadius: BorderRadius.circular(16),
              ),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl ?? '').isEmpty
                  ? const Icon(Icons.category_outlined, color: AppColors.brandPrimary)
                  : HubImage(url: imageUrl, fit: BoxFit.cover, width: 74, height: 74),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkHeading,
              ),
            ),
            if (category.productCount > 0)
              Text(
                l10n.categoryProductCount(category.productCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
              ),
          ],
        ),
      ),
    );
  }
}

class _TodaysDeals extends ConsumerWidget {
  const _TodaysDeals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref.watch(homeDealsProvider).when(
          loading: () => const _RailSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeader(title: l10n.homeTodaysDeals),
                    _ProductCarousel(products: items),
                  ],
                ),
        );
  }
}

class _CategoryRails extends ConsumerWidget {
  const _CategoryRails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(homeCategoriesProvider).valueOrNull ?? const <Category>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final c in categories.take(kHomeRailCount)) _CategoryRail(category: c),
      ],
    );
  }
}

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ref.watch(homeCategoryRailProvider(category.uid)).when(
          loading: () => const _RailSkeleton(),
          error: (_, __) => const SizedBox.shrink(),
          data: (items) => items.isEmpty
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionHeader(
                      title: category.name,
                      actionLabel: l10n.homeSeeAll,
                      onAction: () => context.push(AppRoutes.category(category.uid)),
                    ),
                    _ProductCarousel(products: items),
                  ],
                ),
        );
  }
}

class _ProductCarousel extends StatelessWidget {
  const _ProductCarousel({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kRailHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: _kCardWidth,
          child: ProductCard(
            product: products[i],
            onTap: () => openProduct(context, products[i]),
          ),
        ),
      ),
    );
  }
}

class _PromoBanners extends ConsumerWidget {
  const _PromoBanners();

  static const List<List<Color>> _palettes = <List<Color>>[
    <Color>[Color(0xFF0F2144), Color(0xFF1E3A6E)],
    <Color>[Color(0xFF14532D), Color(0xFF15803D)],
    <Color>[Color(0xFF4C1D95), Color(0xFF6D28D9)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(homePromosProvider);
    if (promos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        children: [
          for (var i = 0; i < promos.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _PromoCard(promo: promos[i], colors: _palettes[i % _palettes.length]),
          ],
        ],
      ),
    );
  }
}

class _PromoCard extends ConsumerWidget {
  const _PromoCard({required this.promo, required this.colors});

  final PromoTile promo;
  final List<Color> colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.centerStart,
            end: AlignmentDirectional.centerEnd,
            colors: colors,
          ),
        ),
        child: InkWell(
          onTap: promo.url.isEmpty
              ? null
              : () => openStorefrontUrl(context, ref, promo.url, title: promo.title),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [promo.icon, promo.kicker.toUpperCase()]
                            .where((s) => s.isNotEmpty)
                            .join('  '),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        promo.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (promo.text.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          promo.text,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustRow extends ConsumerWidget {
  const _TrustRow();

  static const List<IconData> _icons = <IconData>[
    Icons.verified_user_outlined,
    Icons.lock_outline,
    Icons.local_shipping_outlined,
    Icons.assignment_return_outlined,
    Icons.support_agent_outlined,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(homeTrustProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = (constraints.maxWidth - 12) / 2;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  // An odd last item spans the full row, as in the Figma.
                  width: (i == items.length - 1 && items.length.isOdd)
                      ? constraints.maxWidth
                      : half,
                  child: _TrustTile(item: items[i], icon: _icons[i % _icons.length]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TrustTile extends StatelessWidget {
  const _TrustTile({required this.item, required this.icon});

  final TrustItem item;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: AppColors.surfaceTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: AppColors.brandPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkHeading,
                  ),
                ),
                if (item.text.isNotEmpty)
                  Text(
                    item.text,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── skeletons

class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: SizedBox(
        height: _kRailHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, __) => const SizedBox(width: _kCardWidth, child: ProductCardSkeleton()),
        ),
      ),
    );
  }
}

class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: SizedBox(
        height: 100,
        child: Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              const Shimmer(child: SkeletonBox(width: 74, height: 74)),
            ],
          ],
        ),
      ),
    );
  }
}
