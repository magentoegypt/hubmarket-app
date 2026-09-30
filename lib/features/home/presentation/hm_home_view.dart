import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/hm_link_navigation.dart';
import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/hubapp/hubapp_providers.dart';
import '../../../l10n/l10n.dart';
import '../../deals/presentation/widgets/bundle_card.dart';
import '../../deals/presentation/widgets/deal_countdown.dart';
import '../domain/hm_home.dart';
import '../domain/home_content.dart';
import 'widgets/hm_brand_strip.dart';
import 'widgets/hm_category_chips.dart';
import 'widgets/hm_cms_sections.dart';
import 'widgets/hm_hero.dart';
import 'widgets/home_active_order.dart';
import 'widgets/hm_picked_for_you.dart';
import 'widgets/hm_product_rail.dart';
import 'widgets/hm_section_header.dart';
import 'widgets/hm_store_cards.dart';

/// The admin-laid-out Home (Figma 07, `hmAppHome`): every section in the
/// admin's order, drawn by its type. Sections are built lazily as they
/// scroll in; one with nothing to show is never drawn (the caller passes
/// [HmHome.visibleSections]).
class HmHomeView extends ConsumerWidget {
  const HmHomeView({super.key, required this.sections, required this.onRefresh});

  final List<HmHomeSection> sections;
  final Future<void> Function() onRefresh;

  /// Space between sections (Figma 07 "Body": 28), and after the delivery
  /// strip (16).
  static const double gap = 28;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The active-order card (not an admin section) leads the Home, below a
    // leading delivery strip as in Figma 07.
    final cardAt =
        sections.isNotEmpty &&
            sections.first.type == HmSectionType.deliveryStrip
        ? 1
        : 0;
    return RefreshIndicator(
      color: AppColors.brandPrimary,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: gap),
        itemCount: sections.length + 1,
        itemBuilder: (context, index) {
          if (index == cardAt) {
            // Nothing unless signed in with an open recent order; 12 below
            // plus the next section's 16 make the frame's 28.
            return const HomeActiveOrder(
              key: ValueKey('hm-active-order'),
              padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
            );
          }
          final i = index > cardAt ? index - 1 : index;
          final section = sections[i];
          final top = i == 0
              ? (section.type == HmSectionType.deliveryStrip ? 0.0 : 16.0)
              : sections[i - 1].type == HmSectionType.deliveryStrip
              ? 16.0
              : gap;
          return Padding(
            key: ValueKey('hm-section-${section.id}-${section.type.wire}'),
            padding: EdgeInsets.only(top: top),
            child: HmSectionView(section: section, onRefresh: onRefresh),
          );
        },
      ),
    );
  }
}

/// One Home section by its type.
class HmSectionView extends ConsumerWidget {
  const HmSectionView({super.key, required this.section, this.onRefresh});

  final HmHomeSection section;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final s = section;
    final html = s.cmsBlock?.content ?? '';

    /// The section's "View all": the admin's link, else [fallback] (a list
    /// page the type naturally leads to), else none.
    VoidCallback? more({String? fallback}) {
      final link = s.moreLink;
      if (link != null) {
        return () => openHmLink(context, ref, link, title: s.title);
      }
      if (fallback != null) return () => context.push(fallback);
      return null;
    }

    Widget titled(
      Widget child, {
      String? action,
      VoidCallback? onAction,
      Widget? leading,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s.hasHeader)
          HmSectionHeader(
            title: s.title!,
            subtitle: s.subtitle,
            leading: leading,
            actionLabel: action,
            onAction: onAction,
          ),
        child,
      ],
    );

    switch (s.type) {
      case HmSectionType.deliveryStrip:
        final text = HomeContentParser.plainText(html);
        return text.isEmpty ? const SizedBox.shrink() : HmDeliveryStrip(text: text);
      case HmSectionType.heroBanners:
        final slides = s.slides;
        final tiles = s.tiles;
        return Column(
          children: [
            if (slides.isNotEmpty) HmHeroCarousel(slides: slides),
            if (slides.isNotEmpty && tiles.isNotEmpty)
              const SizedBox(height: HmHomeView.gap),
            if (tiles.isNotEmpty) HmPromoTiles(tiles: tiles),
          ],
        );
      case HmSectionType.categoryChips:
        return titled(
          HmCategoryChips(chips: s.categories),
          action: l10n.filterAll,
          onAction: more(fallback: AppRoutes.categories),
        );
      case HmSectionType.todaysDeals:
        final ends = s.countdownEndsAt;
        return titled(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ends != null)
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: DealCountdownPill(endsAt: ends),
                  ),
                ),
              HmProductRail(products: s.products),
            ],
          ),
          leading: const HmHeaderGlyph(icon: Icons.sell_outlined),
          action: l10n.homeAllDeals,
          onAction: more(fallback: AppRoutes.deals),
        );
      case HmSectionType.pickedForYou:
        return HmPickedForYou(section: s, onRefresh: onRefresh);
      case HmSectionType.featuredStores:
        return titled(
          HmFeaturedStoresRail(stores: s.stores),
          action: l10n.homeAllStores,
          onAction: more(fallback: AppRoutes.stores),
        );
      case HmSectionType.categoryRail:
        return titled(
          HmProductRail(products: s.products),
          action: l10n.homeSeeAll,
          onAction: more(),
        );
      case HmSectionType.bundleDeals:
        return ColoredBox(
          color: AppColors.accentSubtle,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: titled(
              SizedBox(
                height: BundleRailCard.height,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: s.bundles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) =>
                      BundleRailCard(deal: s.bundles[i]),
                ),
              ),
              action: l10n.homeAllBundles,
              onAction: more(fallback: AppRoutes.bundles),
            ),
          ),
        );
      case HmSectionType.cmsPromos:
        final promos = HomeContentParser.promos(html);
        return promos.isEmpty
            ? const SizedBox.shrink()
            : HmPromoBanners(promos: promos);
      case HmSectionType.bestSellers:
        // The admin's link, else the whole ranking (`hmBestSellers`), which
        // only a server with the Hub Market App serves.
        final ranking =
            ref.watch(hubAppStatusProvider) == HubAppStatus.available
            ? AppRoutes.bestSellers
            : null;
        return titled(
          HmProductRail(products: s.products, ranked: true),
          leading: const HmHeaderEmoji('🏆'),
          action: l10n.homeViewAll,
          onAction: more(fallback: ranking),
        );
      case HmSectionType.popularProducts:
      case HmSectionType.productList:
        return titled(
          HmProductRail(products: s.products),
          action: l10n.homeViewAll,
          onAction: more(),
        );
      case HmSectionType.topBrands:
        return titled(
          HmBrandStrip(brands: s.brands),
          action: l10n.homeAllBrands,
          onAction: more(fallback: AppRoutes.brands),
        );
      case HmSectionType.topVendors:
        return titled(
          HmTopVendorsRail(stores: s.stores),
          action: l10n.homeAllVendors,
          onAction: more(fallback: AppRoutes.stores),
        );
      case HmSectionType.newStores:
        return titled(
          HmNewStoresList(stores: s.stores),
          leading: const HmHeaderEmoji('🆕'),
          action: l10n.homeAllStores,
          onAction: more(fallback: AppRoutes.stores),
        );
      case HmSectionType.trustRow:
        final items = HomeContentParser.trust(html);
        return items.isEmpty
            ? const SizedBox.shrink()
            : HmTrustGrid(items: items);
      case HmSectionType.cmsBlock:
        return HmCmsBlockView(html: html);
      case HmSectionType.unknown:
        return const SizedBox.shrink();
    }
  }
}
