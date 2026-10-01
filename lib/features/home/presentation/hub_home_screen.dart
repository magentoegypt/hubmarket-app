import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/hub_scaffold.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/error/failure.dart';
import '../../../core/hubapp/hubapp_providers.dart';
import '../../../core/network/connectivity.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/failure_message.dart';
import '../../../core/widgets/offline_state.dart';
import '../../../core/widgets/shimmer.dart';
import '../../../l10n/l10n.dart';
import '../../catalog/domain/category.dart';
import '../../catalog/presentation/catalog_providers.dart';
import '../../catalog/presentation/category_icons.dart';
import '../../catalog/presentation/search_providers.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import '../../catalog/presentation/widgets/product_skeletons.dart';
import '../../notifications/presentation/notification_bell.dart';
import '../data/home_content_repository.dart';
import '../domain/hm_home.dart';
import 'active_order_providers.dart';
import 'hm_home_providers.dart';
import 'hm_home_view.dart';
import 'home_providers.dart';
import 'widgets/hm_category_chips.dart';
import 'widgets/hm_cms_sections.dart';
import 'widgets/hm_product_rail.dart';
import 'widgets/hm_section_header.dart';
import 'widgets/home_active_order.dart';
import '../../../app/theme/hub_icons.dart';

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
      appBar: _HomeHeader(deliverLine: _HomeHeader.deliverLineFor(context)),
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
    final promise = ref.watch(homePromiseProvider);
    final hasOrder = ref.watch(
      activeOrderProvider.select((order) => order.valueOrNull != null),
    );
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
            // at launch. Sections are 28 pt apart (Figma 07 "Body"), 16 under
            // the strip; each carries its own gap so a collapsed one leaves
            // none.
            child: ListView(
              padding: const EdgeInsets.only(bottom: HmHomeView.gap),
              children: [
                if (promise.isNotEmpty) HmDeliveryStrip(text: promise),
                // Signed in with an open recent order only: 16 under the strip.
                const HomeActiveOrder(),
                _ShopByCategory(top: hasOrder ? HmHomeView.gap : 16),
                for (final c in categories.take(kHomeRailCount))
                  _CategoryRail(key: ValueKey(c.uid), category: c),
                const _PromoBanners(),
                const _TrustRow(),
                const _SellCard(),
              ],
            ),
          );
  }
}

/// While the Home's source is being decided: the category tiles and two
/// product rails as skeletons, laid out where the loaded Home puts them.
class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const NeverScrollableScrollPhysics(),
    children: const [
      _CategorySkeleton(top: 16),
      _RailSkeleton(),
      _RailSkeleton(),
    ],
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

/// The Home header (Figma 07 "Header"), not the shared app bar: the logo
/// lockup and the bell, a 46 px search field ending in the orange search
/// button, and the "Deliver to" row, on navy under the status bar. The drawer
/// and its hamburger are not part of this design.
///
/// Under the status bar it is 2 + 40 (logo row) + 12 + 46 (search) + 12 + the
/// "Deliver to" line + 14: 142 in English, 144 in Arabic, whose captions are a
/// line taller. Like every app bar, its [preferredSize] leaves the status bar
/// out: the Scaffold adds the inset to the slot, and the [SafeArea] inside
/// keeps the content below it.
class _HomeHeader extends ConsumerWidget implements PreferredSizeWidget {
  const _HomeHeader({required this.deliverLine});

  /// The height of the "Deliver to" line: the language's Caption line height
  /// at the reader's text size.
  final double deliverLine;

  /// The Caption line of [context]'s language, as the header needs it.
  static double deliverLineFor(BuildContext context) {
    final caption = AppTextStyles.of(context).caption;
    return MediaQuery.textScalerOf(context).scale(caption.fontSize! * caption.height!);
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(2 + 40 + 12 + 46 + 12 + deliverLine + 14);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Material(
        color: AppColors.brandPrimary,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 2, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      const BrandLogo(height: 36, onDark: true),
                      const Spacer(),
                      // With the unread dot, ringed in the header's navy.
                      const NotificationBell(
                        color: Colors.white,
                        dotBorderColor: AppColors.brandPrimary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _SearchBox(
                  hint:
                      ref.watch(searchHintProvider) ??
                      l10n.homeSearchMarketplaceHint,
                  onTap: () => context.push(AppRoutes.search),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: InkWell(
                    onTap: () => context.push(AppRoutes.addresses),
                    child: SizedBox(
                      height: deliverLine,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            HubIcons.mapPin,
                            size: 16,
                            color: AppColors.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.homeDeliverTo,
                            style: t.caption.copyWith(
                              color: AppColors.onInverseMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.homeChooseArea,
                            style: t.captionStrong.copyWith(color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            HubIcons.chevronDown,
                            size: 14,
                            color: Colors.white,
                          ),
                        ],
                      ),
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

/// The search field (Figma "search"): 46 px, white, radius 12, the hint in
/// Body on the start side and the 50 px orange search button filling the
/// field's end.
class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.hint, required this.onTap});

  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(start: 14),
                    child: Text(
                      hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.body.copyWith(color: AppColors.inkMuted),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 50,
                  height: 46,
                  color: AppColors.accent,
                  alignment: Alignment.center,
                  child: const Icon(
                    HubIcons.search,
                    size: 20,
                    color: Colors.white,
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

// ─────────────────────────────────────────────────────────────── sections

/// Shop by category (Figma 07): the catalogue's top-level categories as the
/// pastel tiles of the admin's Home, each with its Lucide glyph.
class _ShopByCategory extends ConsumerWidget {
  const _ShopByCategory({required this.top});

  /// The space above the section.
  final double top;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(homeCategoriesProvider);
    return categories.when(
      loading: () => _CategorySkeleton(top: top),
      error: (_, __) => const SizedBox.shrink(),
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(top: top),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HmSectionHeader(
                title: l10n.homeShopByCategory,
                actionLabel: l10n.filterAll,
                onAction: () => context.go(AppRoutes.categories),
              ),
              SizedBox(
                height: HmCategoryTile.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => HmCategoryTile(
                    name: items[i].name,
                    tint: kCategoryTints[i % kCategoryTints.length],
                    icon: categoryIcon(items[i].urlKey, items[i].name),
                    count: items[i].productCount,
                    onTap: () => context.push(AppRoutes.category(items[i].uid)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// One category's product rail: its name over "See All" and the cards.
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
              : Padding(
                  padding: const EdgeInsets.only(top: HmHomeView.gap),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HmSectionHeader(
                        title: category.name,
                        actionLabel: l10n.homeSeeAll,
                        onAction: () =>
                            context.push(AppRoutes.category(category.uid)),
                      ),
                      HmProductRail(products: items),
                    ],
                  ),
                ),
        );
  }
}

/// The promo cards of the `hm_home_promos` block.
class _PromoBanners extends ConsumerWidget {
  const _PromoBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promos = ref.watch(homePromosProvider);
    if (promos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: HmHomeView.gap),
      child: HmPromoBanners(promos: promos),
    );
  }
}

/// The trust tiles of the `hm_home_trust` block.
class _TrustRow extends ConsumerWidget {
  const _TrustRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(homeTrustProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: HmHomeView.gap),
      child: HmTrustGrid(items: items),
    );
  }
}

/// "Sell on Hub Market": the `hm_home_sell` block as the navy card — nothing
/// while the store has no such block.
class _SellCard extends ConsumerWidget {
  const _SellCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final html = ref.watch(
      homeCmsBlocksProvider.select(
        (blocks) => blocks.valueOrNull?[HomeCmsBlocks.sell],
      ),
    );
    if ((html ?? '').trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: HmHomeView.gap),
      child: HmCmsBlockView(html: html!, identifier: HomeCmsBlocks.sell),
    );
  }
}

// ─────────────────────────────────────────────────────────────── skeletons

/// A section's title as a skeleton bar (Heading 1's 28 pt line).
class _TitleSkeleton extends StatelessWidget {
  const _TitleSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: SkeletonBox(width: 180, height: 28),
    ),
  );
}

/// A product rail while it loads: title and three cards, as tall as the rail.
class _RailSkeleton extends StatelessWidget {
  const _RailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: HmHomeView.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Shimmer(child: _TitleSkeleton()),
          SizedBox(
            height: ProductCardMetrics.heightFor(context, kHmCardWidth),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => const SizedBox(
                width: kHmCardWidth,
                child: ProductCardSkeleton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The category tiles while they load.
class _CategorySkeleton extends StatelessWidget {
  const _CategorySkeleton({required this.top});

  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Shimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _TitleSkeleton(),
            SizedBox(
              height: HmCategoryTile.height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, __) => const SkeletonBox(
                  width: HmCategoryTile.width,
                  height: HmCategoryTile.height,
                  borderRadius: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
