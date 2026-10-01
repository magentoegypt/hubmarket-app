import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/error/failure.dart';
import '../../../core/hubapp/hubapp_providers.dart';
import '../../../core/network/connectivity.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/failure_message.dart';
import '../../../core/widgets/network_image.dart';
import '../../../core/widgets/offline_state.dart';
import '../../../core/widgets/shimmer.dart';
import '../../../l10n/l10n.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/domain/product.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/product_navigation.dart';
import '../../catalog/presentation/search_providers.dart';
import '../../catalog/presentation/storefront_links.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import '../../catalog/presentation/widgets/product_skeletons.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../domain/hm_home.dart';
import '../domain/home_content.dart';
import 'active_order_providers.dart';
import 'hm_home_providers.dart';
import 'hm_home_view.dart';
import 'home_providers.dart';
import 'widgets/home_active_order.dart';
import 'widgets/home_skeleton.dart';
import '../../../app/theme/hub_icons.dart';

/// Carousel card width (Figma v2/v3): 152 pt so the next card peeks ~30%.
const double _kCardWidth = 152;

/// Hub Market Home (Figma "07 Home", v3).
///
/// With the Hub Market App API (Build 2) the Home is the admin's layout from
/// `hmAppHome` ([HmHomeView]). Without it — the module not deployed, the probe
/// unable to tell, or `hmAppHome` failing or empty — it is Build 1
/// ([_Build1Home]), exactly as before: categories and products from the
/// catalogue, the promise strip, promo cards and trust row from the
/// storefront's own CMS blocks, with lazy rails and Retry. A section whose
/// source is empty collapses — nothing is hard-coded or invented.
class HubHomeScreen extends ConsumerWidget {
  const HubHomeScreen({super.key});

  Future<void> _reloadHubApp(WidgetRef ref) async {
    ref
      ..invalidate(hmHomeProvider)
      ..invalidate(activeOrderProvider);
    try {
      await ref.read(hmHomeProvider.future);
    } catch (_) {
      // A failed Home falls back to Build 1, which has its own retry.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hubApp = ref.watch(hubAppProvider);
    final Widget body;
    if (hubApp.isLoading && !hubApp.hasValue) {
      // The first probe is still out (usually settled during the splash).
      body = const _HomeLoading();
    } else if (hubApp.valueOrNull?.isAvailable ?? false) {
      body = ref.watch(hmHomeProvider).when(
        skipLoadingOnRefresh: true,
        loading: () => const _HomeLoading(),
        error: (_, __) => const _Build1Home(),
        data: (home) {
          final sections =
              home?.visibleSections(DateTime.now()) ?? const <HmHomeSection>[];
          // Only placements (the active-order card) is no Home either.
          return !hmHomeHasContent(sections)
              ? const _Build1Home()
              : HmHomeView(
                  sections: sections,
                  onRefresh: () => _reloadHubApp(ref),
                );
        },
      );
    } else {
      body = const _Build1Home();
    }
    return HubScaffold(
      currentTab: AppTab.home,
      showSearch: false,
      appBar: const _HomeHeader(),
      body: body,
    );
  }
}

/// The Build 1 Home: catalogue rails and the storefront's CMS blocks.
class _Build1Home extends ConsumerWidget {
  const _Build1Home();

  Future<void> _reload(WidgetRef ref) async {
    ref
      ..invalidate(homeCmsBlocksProvider)
      ..invalidate(categoryTreeProvider)
      ..invalidate(homeCategoryRailProvider)
      ..invalidate(activeOrderProvider);
    // The Hub Market App may be back (a probe that couldn't tell, or an
    // hmAppHome that failed): ask again alongside.
    final hubApp = ref.read(hubAppProvider).valueOrNull;
    if (hubApp?.isAvailable ?? false) {
      ref.invalidate(hmHomeProvider);
    } else {
      unawaited(ref.read(hubAppProvider.notifier).retryIfUnknown());
    }
    try {
      await ref.read(homeCategoriesProvider.future);
    } catch (_) {
      // A failed feed collapses its own section; nothing to surface here.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(homeCategoriesProvider);
    final categories = categoriesAsync.valueOrNull ?? const <Category>[];
    // Without the category tree Home has nothing to show but the CMS strip, so
    // a failed load (the backend sheds load with 503s) gets a retry instead of
    // a blank page. While a retry runs, the skeletons show again.
    final unavailable = categoriesAsync.hasError &&
        !categoriesAsync.hasValue &&
        !categoriesAsync.isLoading;
    return unavailable
        ? _HomeUnavailable(
            error: categoriesAsync.error!,
            onRetry: () => _reload(ref),
          )
        : RefreshIndicator(
            color: AppColors.brandPrimary,
            onRefresh: () => _reload(ref),
            // Each rail is its own list child, so its product query only
            // starts when it scrolls near the viewport instead of all six
            // at launch.
            child: ListView(
              padding: const EdgeInsets.only(bottom: 28),
              children: [
                const _PromiseStrip(),
                // Signed in with an open recent order only.
                const HomeActiveOrder(),
                const _ShopByCategory(),
                for (final c in categories.take(kHomeRailCount))
                  _CategoryRail(key: ValueKey(c.uid), category: c),
                const _PromoBanners(),
                const _TrustRow(),
              ],
            ),
          );
  }
}

/// While the Home's source is being decided: the frame's loading page (Figma
/// S4).
class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) => const SingleChildScrollView(
    physics: NeverScrollableScrollPhysics(),
    child: HomeSkeleton(),
  );
}

class _HomeUnavailable extends ConsumerWidget {
  const _HomeUnavailable({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No network: the designed offline state (Figma S3), not an error line.
    if (isNetworkFailure(error) || ref.watch(isOfflineProvider)) {
      return OfflineState(onRetry: onRetry);
    }
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(HubIcons.cloudOff, size: 40, color: AppColors.inkMuted),
            const SizedBox(height: 12),
            Text(
              error is Failure
                  ? failureMessage(context, error as Failure)
                  : l10n.errorGeneric,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────── header

class _HomeHeader extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeHeader();

  static const double _contentHeight = 4 + 48 + 8 + 46 + 10 + 20 + 12;

  @override
  Size get preferredSize {
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final top = view.viewPadding.top / view.devicePixelRatio;
    return Size.fromHeight(top + _contentHeight);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                    // With the unread dot, as in the app bar.
                    const NotificationBell(
                      color: Colors.white,
                      icon: HubIcons.bell,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: _SearchBox(
                  hint:
                      ref.watch(searchHintProvider) ??
                      l10n.homeSearchMarketplaceHint,
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
                        HubIcons.mapPin,
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
                      const Icon(HubIcons.chevronDown, size: 16, color: Colors.white),
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
                child: const Icon(HubIcons.search, color: Colors.white),
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
          const Icon(HubIcons.truck, size: 16, color: AppColors.accentStrong),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
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
              style: TextStyle(
                // Playfair Display has no Arabic glyphs; Arabic titles keep
                // the theme's Arabic face.
                fontFamily: Localizations.localeOf(context).languageCode == 'ar'
                    ? null
                    : AppTheme.displayFont,
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
                  const Icon(HubIcons.arrowRight, size: 16),
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
              height: 140,
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
                  ? const Icon(HubIcons.layoutGrid, color: AppColors.brandPrimary)
                  : HubImage(url: imageUrl, fit: BoxFit.cover, width: 74, height: 74),
            ),
            const SizedBox(height: 6),
            Text(
              category.name,
              maxLines: 2,
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

class _CategoryRail extends ConsumerWidget {
  const _CategoryRail({super.key, required this.category});

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
      height: ProductCardMetrics.heightFor(context, _kCardWidth),
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
                  child: Icon(HubIcons.arrowRight, color: Colors.white, size: 18),
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
    HubIcons.shieldCheck,
    HubIcons.lock,
    HubIcons.truck,
    HubIcons.rotateCcw,
    HubIcons.headset,
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
        height: ProductCardMetrics.heightFor(context, _kCardWidth),
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
