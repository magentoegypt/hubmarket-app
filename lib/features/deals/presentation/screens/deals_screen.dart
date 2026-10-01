import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/presentation/product_navigation.dart';
import '../../../catalog/presentation/widgets/product_card.dart';
import '../../../catalog/presentation/widgets/sort_sheet.dart';
import '../../domain/deals.dart';
import '../deals_controller.dart';
import '../widgets/deal_countdown.dart';
import '../widgets/hm_list_widgets.dart';
import '../widgets/list_states.dart';

/// Today's Deals (Figma 10b, `hmDeals`): the countdown banner, department
/// chips, the count with the sort and the Filters sheet, and the deals in a
/// two-column grid. Filters and sorts are the server's, over the day's whole
/// ranking; the chips and their counts come from it too.
class DealsScreen extends ConsumerWidget {
  const DealsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(dealsControllerProvider);
    final controller = ref.read(dealsControllerProvider.notifier);
    final error = state.error;

    final Widget body;
    if (state.isLoading && state.items.isEmpty && state.filters.isEmpty) {
      body = const HmGridSkeleton();
    } else if (error != null && state.items.isEmpty) {
      body = HmListError(
        error: error,
        onRetry: controller.refresh,
        emptyTitle: l10n.dealsEmpty,
      );
    } else if (state.items.isEmpty &&
        !state.isLoading &&
        state.filters.isEmpty) {
      body = EmptyState(icon: HubIcons.tag, title: l10n.dealsEmpty);
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
    final deals = state.items;
    final ends = state.countdownEndsAt;
    final filters = state.filters;
    final chips = state.filtersSupported
        ? state.categories
        : const <DealCategory>[];
    return RefreshIndicator(
      color: AppColors.brandPrimary,
      onRefresh: controller.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) controller.loadMore();
          return false;
        },
        child: CustomScrollView(
          slivers: [
            if (ends != null)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(child: DealsEndBanner(endsAt: ends)),
              ),
            if (chips.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.only(top: 12),
                sliver: SliverToBoxAdapter(
                  child: HmChipRow(
                    chips: [
                      HubChip(
                        label: l10n.dealsAllChip,
                        selected: filters.categoryId == null,
                        onTap: () => controller.selectCategory(null),
                      ),
                      for (final c in chips)
                        HubChip(
                          label: c.name,
                          selected: filters.categoryId == c.id,
                          onTap: () => controller.selectCategory(
                            filters.categoryId == c.id ? null : c.id,
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
                        l10n.dealsCount(state.totalCount),
                        style: t.caption.copyWith(color: AppColors.inkMuted),
                      ),
                    ),
                    if (state.filtersSupported) ...[
                      HmPillButton(
                        icon: HubIcons.arrowUpDown,
                        label: dealsSortLabel(l10n, filters.sort),
                        onTap: () => _pickSort(context, filters.sort),
                      ),
                      const SizedBox(width: 8),
                      HmPillButton(
                        icon: HubIcons.slidersHorizontal,
                        label: filters.isEmpty
                            ? l10n.filtersLabel
                            : '${l10n.filtersLabel} · ${_activeCount(filters)}',
                        onTap: () => _openFilters(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (state.isLoading && deals.isEmpty)
              const SliverToBoxAdapter(child: HmGridSkeleton())
            else if (deals.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      EmptyState(icon: HubIcons.tag, title: l10n.dealsNoMatch),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () =>
                            controller.apply(DealsFilters(sort: filters.sort)),
                        child: Text(l10n.filterClearAllLabel),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverGrid.builder(
                  gridDelegate: hmGridDelegate(context),
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
      ),
    );
  }

  /// How many filters narrow the list (the sort aside).
  static int _activeCount(DealsFilters filters) =>
      (filters.categoryId == null ? 0 : 1) +
      (filters.minDiscount == null ? 0 : 1);

  Future<void> _pickSort(BuildContext context, DealsSort current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showHubBottomSheet<DealsSort>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SortChoiceSheet<DealsSort>(
        current: current,
        choices: [
          for (final sort in DealsSort.values)
            (value: sort, label: dealsSortLabel(l10n, sort)),
        ],
      ),
    );
    if (picked != null) controller.setSort(picked);
  }

  Future<void> _openFilters(BuildContext context) async {
    final picked = await showHubBottomSheet<DealsFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      // Figma 11's scrim: the brand navy at 55 %.
      barrierColor: AppColors.brandPrimary.withValues(alpha: 0.55),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DealsFilterSheet(
        initial: state.filters,
        categories: state.categories,
      ),
    );
    if (picked != null) controller.apply(picked);
  }
}

/// The label of a deals sort, in the sort sheet, the pill and the Filters
/// sheet.
String dealsSortLabel(AppLocalizations l10n, DealsSort sort) => switch (sort) {
  DealsSort.biggestDiscount => l10n.dealsSortBiggestDiscount,
  DealsSort.priceLowHigh => l10n.sortPriceLowHigh,
  DealsSort.priceHighLow => l10n.sortPriceHighLow,
  DealsSort.endingSoon => l10n.dealsSortEndingSoon,
  DealsSort.newest => l10n.sortNewest,
};

/// The Filters sheet of Today's Deals, built as Figma 11's: a grabber, the
/// "Filters" header with Reset, one section per filter — the sort, a minimum
/// discount and the department, chips under a Title — and the full-width
/// button on a rule. Returns the chosen [DealsFilters]; Reset clears them,
/// keeping the sheet open.
class DealsFilterSheet extends StatefulWidget {
  const DealsFilterSheet({
    super.key,
    required this.initial,
    this.categories = const <DealCategory>[],
  });

  final DealsFilters initial;

  /// The server's department chips; the section is left out without them.
  final List<DealCategory> categories;

  @override
  State<DealsFilterSheet> createState() => _DealsFilterSheetState();
}

class _DealsFilterSheetState extends State<DealsFilterSheet> {
  late DealsFilters _filters = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // The home indicator / navigation bar: the sheet is already lifted by it
    // (showHubBottomSheet), so the footer only tops up to 12 px when there is
    // less than that — Figma's 34 px under the button is the iPhone's.
    final view = View.of(context);
    final footerBottom = (12 - view.padding.bottom / view.devicePixelRatio)
        .clamp(0.0, 12.0);

    Widget section(String title, List<Widget> chips) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.title.copyWith(color: AppColors.inkHeading)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
      ],
    );

    final sections = <Widget>[
      section(l10n.dealsFilterSortBy, [
        for (final sort in DealsSort.values)
          HubChip(
            label: dealsSortLabel(l10n, sort),
            selected: _filters.sort == sort,
            onTap: () =>
                setState(() => _filters = _filters.copyWith(sort: sort)),
          ),
      ]),
      section(l10n.filterDiscountLabel, [
        HubChip(
          label: l10n.dealsFilterAnyDiscount,
          selected: _filters.minDiscount == null,
          onTap: () =>
              setState(() => _filters = _filters.copyWith(minDiscount: null)),
        ),
        for (final percent in DealsFilters.discountSteps)
          HubChip(
            label: l10n.filterDiscountOption(percent),
            selected: _filters.minDiscount == percent,
            onTap: () => setState(
              () => _filters = _filters.copyWith(minDiscount: percent),
            ),
          ),
      ]),
      if (widget.categories.isNotEmpty)
        section(l10n.dealsFilterCategory, [
          HubChip(
            label: l10n.dealsAllChip,
            selected: _filters.categoryId == null,
            onTap: () =>
                setState(() => _filters = _filters.copyWith(categoryId: null)),
          ),
          for (final c in widget.categories)
            HubChip(
              label: '${c.name} (${c.count})',
              selected: _filters.categoryId == c.id,
              onTap: () => setState(
                () => _filters = _filters.copyWith(categoryId: c.id),
              ),
            ),
        ]),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The grabber: 40 x 4, 10 px from the top.
        const Padding(
          padding: EdgeInsets.only(top: 10, bottom: 4),
          child: Center(
            child: SizedBox(
              width: 40,
              height: 4,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
          ),
        ),
        // 8 above and 12 below the 24 px title, as Figma's header; Reset is a
        // 32 px target centred on the same line.
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.filtersLabel,
                    style: t.heading2.copyWith(color: AppColors.inkHeading),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _filters = const DealsFilters()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accentStrong,
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: t.bodyStrong,
                  ),
                  child: Text(l10n.filterResetLabel),
                ),
              ],
            ),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, s) in sections.indexed) ...[
                  if (i > 0) const SizedBox(height: 22),
                  s,
                ],
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.borderSubtle)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, footerBottom),
            child: HubButton(
              label: l10n.filterApplyLabel,
              onPressed: () => Navigator.of(context).pop(_filters),
            ),
          ),
        ),
      ],
    );
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
            const Icon(HubIcons.clock, size: 22, color: Colors.white),
            const SizedBox(width: 10),
            // No "new deals every day at midnight" line: when deals refresh
            // is the store's business, not a promise the app makes (QA02).
            Expanded(
              child: Text(
                l10n.dealsEndIn,
                style: t.captionStrong.copyWith(color: Colors.white),
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
