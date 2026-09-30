import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../deals_controller.dart';
import '../widgets/deal_countdown.dart';
import '../widgets/hm_list_widgets.dart';
import '../widgets/list_states.dart';

/// Today's Deals (Figma 10b, `hmDeals`): the countdown banner, category chips,
/// the count with the sort, and the deals in a two-column grid — deepest
/// discount first unless another sort is picked.
class DealsScreen extends ConsumerWidget {
  const DealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dealsControllerProvider);
    final controller = ref.read(dealsControllerProvider.notifier);
    final error = state.error;

    final Widget body;
    if (state.isLoading && state.items.isEmpty) {
      body = const HmGridSkeleton();
    } else if (error != null && state.items.isEmpty) {
      body = HmListError(
        error: error,
        onRetry: controller.refresh,
        emptyTitle: l10n.dealsEmpty,
      );
    } else if (state.items.isEmpty) {
      body = EmptyState(icon: Icons.local_offer_outlined, title: l10n.dealsEmpty);
    } else {
      body = _DealsList(state: state, controller: controller);
    }

    return HubScaffold(
      currentTab: AppTab.home,
      appBar: HmTitleAppBar(title: l10n.homeTodaysDeals),
      body: body,
    );
  }
}

class _DealsList extends StatelessWidget {
  const _DealsList({required this.state, required this.controller});

  final DealsState state;
  final DealsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final deals = state.visible;
    final ends = state.countdownEndsAt;
    final categories = state.categories;
    return RefreshIndicator(
      color: AppColors.brandPrimary,
      onRefresh: controller.refresh,
      child: CustomScrollView(
        slivers: [
          if (ends != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: DealsEndBanner(endsAt: ends)),
            ),
          if (categories.length > 1)
            SliverPadding(
              padding: const EdgeInsets.only(top: 12),
              sliver: SliverToBoxAdapter(
                child: HmChipRow(
                  chips: [
                    HmFilterChip(
                      label: l10n.dealsAllChip,
                      selected: state.categoryUid == null,
                      onTap: () => controller.selectCategory(null),
                    ),
                    for (final c in categories)
                      HmFilterChip(
                        label: c.name,
                        selected: state.categoryUid == c.uid,
                        onTap: () => controller.selectCategory(
                          state.categoryUid == c.uid ? null : c.uid,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.dealsCount(state.visibleCount),
                      style: t.caption.copyWith(color: AppColors.inkMuted),
                    ),
                  ),
                  HmPillButton(
                    icon: Icons.swap_vert,
                    label: _sortLabel(l10n, state.sort),
                    onTap: () => _pickSort(context, state.sort),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 173 / 283,
              ),
              itemCount: deals.length,
              itemBuilder: (context, i) => ProductCard(
                product: deals[i],
                onTap: () => openProduct(context, deals[i]),
              ),
            ),
          ),
          if (state.isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  static String _sortLabel(AppLocalizations l10n, DealsSort sort) =>
      switch (sort) {
        DealsSort.biggestDiscount => l10n.dealsSortBiggestDiscount,
        DealsSort.priceLowHigh => l10n.sortPriceLowHigh,
        DealsSort.priceHighLow => l10n.sortPriceHighLow,
      };

  Future<void> _pickSort(BuildContext context, DealsSort current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<DealsSort>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in DealsSort.values)
              ListTile(
                title: Text(_sortLabel(l10n, sort)),
                trailing: sort == current
                    ? const Icon(Icons.check, color: AppColors.brandPrimary)
                    : null,
                onTap: () => Navigator.pop(context, sort),
              ),
          ],
        ),
      ),
    );
    if (picked != null) controller.setSort(picked);
  }
}

/// The orange "Deals end in" banner (Figma 10b "countdown").
class DealsEndBanner extends StatelessWidget {
  const DealsEndBanner({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return DealCountdown(
      endsAt: endsAt,
      builder: (context, left) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule_rounded, size: 22, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.dealsEndIn,
                    style: t.captionStrong.copyWith(color: Colors.white),
                  ),
                  Text(
                    l10n.dealsNewEveryDay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.micro.copyWith(color: Colors.white),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.brandPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: CountdownText(
                left: left,
                style: t.title.copyWith(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
