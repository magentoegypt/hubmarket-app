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
import 'active_order_providers.dart';
import 'widgets/hm_brand_strip.dart';
import 'widgets/hm_category_chips.dart';
import 'widgets/hm_cms_sections.dart';
import 'widgets/hm_hero.dart';
import 'widgets/home_active_order.dart';
import 'widgets/hm_picked_for_you.dart';
import 'widgets/hm_product_rail.dart';
import 'widgets/hm_section_header.dart';
import 'widgets/hm_store_cards.dart';
import '../../../app/theme/hub_icons.dart';

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
    // The active-order card is an entry only while there is an order to show,
    // so the gaps around it are those of the Home actually drawn.
    final withCard = ref.watch(
      activeOrderProvider.select((order) => order.valueOrNull != null),
    );
    final entries = hmHomeEntries(sections, withActiveOrder: withCard);
    return RefreshIndicator(
      color: AppColors.brandPrimary,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: gap),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final top = hmHomeGapBefore(entries, index);
          final section = entry.section;
          if (entry.isActiveOrder) {
            return Padding(
              key: const ValueKey('hm-active-order'),
              padding: EdgeInsets.only(top: top),
              child: HmActiveOrderSection(section: section),
            );
          }
          return Padding(
            key: ValueKey('hm-section-${section!.id}-${section.type.wire}'),
            padding: EdgeInsets.only(top: top),
            child: HmSectionView(section: section, onRefresh: onRefresh),
          );
        },
      ),
    );
  }
}

/// One item of the Build 2 Home list: an admin section, or the active-order
/// card.
@immutable
class HmHomeEntry {
  const HmHomeEntry.section(HmHomeSection this.section) : isActiveOrder = false;

  /// The card at the admin's ACTIVE_ORDER [section] (its optional title), or
  /// at the default place when there is none.
  const HmHomeEntry.activeOrder([this.section]) : isActiveOrder = true;

  final HmHomeSection? section;
  final bool isActiveOrder;

  bool get isDeliveryStrip =>
      !isActiveOrder && section?.type == HmSectionType.deliveryStrip;
}

/// The Home's entries in order. With [withActiveOrder] (a signed-in customer
/// with an open recent order) the card is drawn once: at the admin's first
/// ACTIVE_ORDER section, else where Figma 07 puts it — first, or under a
/// leading delivery strip. Without it no entry is left for the card, and an
/// ACTIVE_ORDER section never is one.
List<HmHomeEntry> hmHomeEntries(
  List<HmHomeSection> sections, {
  required bool withActiveOrder,
}) {
  final placed = sections.indexWhere(
    (section) => section.type == HmSectionType.activeOrder,
  );
  final entries = <HmHomeEntry>[
    for (final (i, section) in sections.indexed)
      if (section.type != HmSectionType.activeOrder)
        HmHomeEntry.section(section)
      else if (i == placed && withActiveOrder)
        HmHomeEntry.activeOrder(section),
  ];
  if (placed < 0 && withActiveOrder) {
    final at = entries.isNotEmpty && entries.first.isDeliveryStrip ? 1 : 0;
    entries.insert(at, const HmHomeEntry.activeOrder());
  }
  return entries;
}

/// The space above entry [index] (Figma 07 "Body"): 16 at the top (none for a
/// leading delivery strip) and after the strip, [HmHomeView.gap] elsewhere.
double hmHomeGapBefore(List<HmHomeEntry> entries, int index) {
  if (index == 0) return entries.first.isDeliveryStrip ? 0 : 16;
  return entries[index - 1].isDeliveryStrip ? 16 : HmHomeView.gap;
}

/// The active-order card as a Build 2 Home entry: the admin's optional title
/// over [ActiveOrderCard]; nothing without an open order (see
/// [activeOrderProvider]).
class HmActiveOrderSection extends ConsumerWidget {
  const HmActiveOrderSection({super.key, this.section});

  /// The admin's ACTIVE_ORDER section; null at the default place.
  final HmHomeSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(activeOrderProvider).valueOrNull;
    if (order == null) return const SizedBox.shrink();
    final card = Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
      child: ActiveOrderCard(order: order),
    );
    final s = section;
    if (s == null || !s.hasHeader) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HmSectionHeader(title: s.title!, subtitle: s.subtitle),
        card,
      ],
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
          leading: const HmHeaderGlyph(icon: HubIcons.tag),
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
        return HmCmsBlockView(html: html, identifier: s.cmsBlock?.identifier);
      case HmSectionType.activeOrder:
        return HmActiveOrderSection(section: s);
      case HmSectionType.unknown:
        return const SizedBox.shrink();
    }
  }
}
