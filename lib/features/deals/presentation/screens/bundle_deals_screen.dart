import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../home/domain/hm_home.dart';
import '../../../home/presentation/hm_home_providers.dart';
import '../../domain/deals.dart';
import '../bundle_deals_controller.dart';
import '../widgets/bundle_card.dart';
import '../widgets/hm_list_widgets.dart';
import '../widgets/list_states.dart';
import '../../../../app/theme/hub_icons.dart';

/// Bundle deals (Figma 10c, `hmBundleDeals`): the navy intro (the Home's
/// bundles title and subtitle when the admin set them — see
/// [bundlesSectionHeader]) with the live stats, category chips, and one card
/// per bundle — its items side by side, saving, rating, seller, price and
/// "Add bundle".
class BundleDealsScreen extends ConsumerWidget {
  const BundleDealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(bundleDealsControllerProvider);
    final controller = ref.read(bundleDealsControllerProvider.notifier);
    final error = state.error;
    final firstLoad = state.isLoading && state.items.isEmpty;

    final Widget body;
    if (error != null && state.items.isEmpty && !state.isLoading) {
      body = HmListError(
        error: error,
        onRetry: controller.refresh,
        emptyTitle: l10n.bundlesEmpty,
        emptyIcon: HubIcons.package,
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.brandPrimary,
        onRefresh: controller.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) controller.loadMore();
            return false;
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: [
              if (!firstLoad) ...[
                _BundlesIntro(page: state.page),
                const SizedBox(height: 14),
              ],
              if (state.categories.length > 1) ...[
                HmChipRow(
                  padded: false,
                  chips: [
                    HubChip(
                      label: l10n.bundlesAllChip,
                      selected: state.categoryId == null,
                      onTap: () => controller.selectCategory(null),
                    ),
                    for (final c in state.categories)
                      HubChip(
                        label: c.name,
                        selected: state.categoryId == c.id,
                        onTap: () => controller.selectCategory(
                          state.categoryId == c.id ? null : c.id,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              if (state.isLoading && state.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.items.isEmpty)
                EmptyState(icon: HubIcons.package, title: l10n.bundlesEmpty)
              else
                for (final (i, deal) in state.items.indexed) ...[
                  if (i > 0) const SizedBox(height: 14),
                  BundleListCard(deal: deal),
                ],
              if (state.isLoadingMore)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      );
    }

    return HubScaffold(
      currentTab: AppTab.home,
      appBar: HmTitleAppBar(title: l10n.bundlesTitle),
      body: body,
    );
  }
}

/// The admin's own words for bundles: the title and subtitle of the Home
/// layout's BUNDLE_DEALS section (`hmAppHome`), when the Home has read it —
/// this screen never loads the Home just for them. Null without a titled
/// section; the intro then keeps neutral interface wording (QA02: no
/// marketing claims written into the app).
({String title, String? subtitle})? bundlesSectionHeader(WidgetRef ref) {
  if (!ref.exists(hmHomeProvider)) return null;
  final home = ref.watch(hmHomeProvider).valueOrNull;
  if (home == null) return null;
  final now = DateTime.now();
  for (final section in home.sections) {
    if (section.type != HmSectionType.bundleDeals ||
        !section.isLiveAt(now) ||
        !section.hasHeader) {
      continue;
    }
    final subtitle = section.subtitle?.trim();
    return (
      title: section.title!.trim(),
      subtitle: subtitle == null || subtitle.isEmpty ? null : subtitle,
    );
  }
  return null;
}

class _BundlesIntro extends ConsumerWidget {
  const _BundlesIntro({required this.page});

  final BundleDealPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final admin = bundlesSectionHeader(ref);
    final title = admin?.title ?? l10n.bundlesHeroTitle;
    // The admin's subtitle goes with their title; without either, the app's
    // neutral line.
    final body = admin == null ? l10n.bundlesHeroBody : admin.subtitle;
    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(value, style: t.title.copyWith(color: Colors.white)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: t.micro.copyWith(color: const Color(0xFFCBD3E2)),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.brandPrimary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.heading2.copyWith(color: Colors.white)),
          if (body != null) ...[
            const SizedBox(height: 10),
            Text(
              body,
              style: t.caption.copyWith(color: const Color(0xFFCBD3E2)),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF2A3B5E))),
            ),
            child: Row(
              children: [
                stat('${page.totalCount}', l10n.bundlesStatActive),
                if (page.maxDiscountPercent > 0) ...[
                  const SizedBox(width: 8),
                  stat(
                    l10n.bundlesStatUpTo(page.maxDiscountPercent),
                    l10n.bundlesStatMaxSaving,
                  ),
                ],
                if (page.sellerCount > 0) ...[
                  const SizedBox(width: 8),
                  stat('${page.sellerCount}', l10n.bundlesStatVendors),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A bundle in the 10c list: its items side by side, the discount and count,
/// name, rating and seller, price with the saving, and "Add bundle".
class BundleListCard extends StatelessWidget {
  const BundleListCard({super.key, required this.deal});

  final BundleDeal deal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final images = deal.thumbnails.isNotEmpty
        ? deal.thumbnails.take(3).toList()
        : [if (deal.imageUrl != null) deal.imageUrl!];
    final rating = deal.rating;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openBundle(context, deal),
        // Everything sits inside the 1 px outline, as Figma's border-box: the
        // card is 2 px taller than its content.
        child: Padding(
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 112,
                color: AppColors.surfaceSubtle,
                child: Row(
                  children: [
                    if (images.isEmpty)
                      const Expanded(child: HubImage(url: null))
                    else
                      for (final (i, url) in images.indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          child: HubImage(url: url, fit: BoxFit.cover),
                        ),
                      ],
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (deal.hasSaving) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accentSale,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              l10n.bundleListBadge(deal.discountPercent),
                              style: t.micro.copyWith(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (deal.itemCount > 0)
                          Text(
                            l10n.bundleItemCount(deal.itemCount),
                            style: t.caption.copyWith(
                              color: AppColors.inkMuted,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      deal.name,
                      style: t.title.copyWith(color: AppColors.inkHeading),
                    ),
                    if (rating != null || deal.seller != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (rating != null) ...[
                            _Stars(rating: rating),
                            const SizedBox(width: 6),
                            Text(
                              '${rating.toStringAsFixed(1)} (${deal.reviewCount})',
                              style: t.caption.copyWith(
                                color: AppColors.inkMuted,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (deal.seller != null)
                            Flexible(
                              child: Text(
                                // The dot only separates it from a rating before it.
                                '${rating != null ? '· ' : ''}'
                                '${l10n.bundleSoldBy(deal.seller!.name)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.caption.copyWith(
                                  color: AppColors.info,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    BundlePriceRow(deal: deal, compactSaving: true),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      // The theme's FilledButton is Figma's Button: 52 px,
                      // radius 12, navy, EN/Button label.
                      child: FilledButton.icon(
                        onPressed: () => openBundle(context, deal),
                        icon: const Icon(HubIcons.shoppingCart, size: 20),
                        label: Text(l10n.bundleListAdd),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five 12 px stars, 2 apart: as many lit as the rating rounds to (4.5 lights
/// five, 4.2 four), the rest in the unlit grey — Figma 10c.
class _Stars extends StatelessWidget {
  const _Stars({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final lit = rating.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++) ...[
          if (star > 1) const SizedBox(width: 2),
          Icon(
            Icons.star_rounded,
            size: 12,
            color: star <= lit ? AppColors.ratingStar : AppColors.ratingEmpty,
          ),
        ],
      ],
    );
  }
}
