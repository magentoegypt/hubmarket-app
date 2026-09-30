import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../deals/presentation/widgets/hm_list_widgets.dart';
import '../../../deals/presentation/widgets/list_states.dart';
import '../../data/brands_provider.dart';
import '../../data/catalog_repository.dart';
import '../../domain/brand.dart';
import '../brand_results_controller.dart';
import '../plp_controller.dart';
import '../product_navigation.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/product_card.dart';
import '../widgets/sort_sheet.dart';

/// The brand a page is for: [brand] when the caller had it, else looked up by
/// its url_key among `hmBrands`; null when there is no such brand.
final brandByUrlKeyProvider = FutureProvider.autoDispose.family<Brand?, String>((
  ref,
  urlKey,
) async {
  final key = urlKey.trim().toLowerCase();
  final brands = await ref.watch(brandsProvider.future);
  for (final brand in brands) {
    if (brand.urlKey.toLowerCase() == key) return brand;
  }
  return null;
});

/// A brand's page (Figma 10e): its logo, product and store counts, category
/// chips, sort and filters over `products(filter: {mgs_brand: {eq: id}})`.
///
/// The counts are `hmBrands`' own (`product_count`, `seller_count`): "from N
/// stores" whenever the brand has products. A brand handed over without them
/// (the Home's brand strip) takes them from [brandsProvider].
class BrandPageScreen extends ConsumerWidget {
  const BrandPageScreen({super.key, required this.urlKey, this.brand});

  final String urlKey;
  final Brand? brand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final known = brand;
    if (known != null) return _BrandPage(brand: known);
    return ref.watch(brandByUrlKeyProvider(urlKey)).when(
      loading: () => HubScaffold(
        currentTab: AppTab.home,
        appBar: HmTitleAppBar(title: '', actions: const <Widget>[]),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => HubScaffold(
        currentTab: AppTab.home,
        appBar: HmTitleAppBar(title: '', actions: const <Widget>[]),
        body: HmListError(
          error: error,
          onRetry: () => ref.invalidate(brandsProvider),
          emptyTitle: l10n.brandsEmpty,
          emptyIcon: Icons.storefront_outlined,
        ),
      ),
      data: (found) => found == null
          ? HubScaffold(
              currentTab: AppTab.home,
              appBar: HmTitleAppBar(title: '', actions: const <Widget>[]),
              body: EmptyState(
                icon: Icons.storefront_outlined,
                title: l10n.brandsEmpty,
              ),
            )
          : _BrandPage(brand: found),
    );
  }
}

class _BrandPage extends ConsumerWidget {
  const _BrandPage({required this.brand});

  final Brand brand;

  static const String _categoryCode = 'category_uid';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final optionId = brand.optionId;
    final actions = [
      IconButton(
        icon: const Icon(Icons.search, size: 22),
        color: AppColors.inkHeading,
        onPressed: () => context.push(AppRoutes.search),
      ),
      if (brand.url.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.share_outlined, size: 22),
          color: AppColors.inkHeading,
          tooltip: l10n.actionShare,
          onPressed: () =>
              SharePlus.instance.share(ShareParams(text: '${brand.title}\n${brand.url}')),
        ),
      const SizedBox(width: 4),
    ];
    if (optionId == null) {
      return HubScaffold(
        currentTab: AppTab.home,
        appBar: HmTitleAppBar(title: brand.title, actions: actions),
        body: EmptyState(icon: Icons.storefront_outlined, title: l10n.brandsEmpty),
      );
    }

    final state = ref.watch(brandResultsControllerProvider(optionId));
    final controller = ref.read(brandResultsControllerProvider(optionId).notifier);
    final counted = brand.sellerCount != null
        ? brand
        : ref
                  .watch(brandsProvider)
                  .valueOrNull
                  ?.where((b) => b.optionId == optionId)
                  .firstOrNull ??
              brand;
    final products = counted.productCount;
    final stores = counted.sellerCount;
    final summary = [
      l10n.hmProductCount(products ?? state.totalCount),
      if (stores != null && stores > 0) l10n.brandFromStores(stores),
    ].join(' · ');

    final categories = [
      for (final agg in state.aggregations)
        if (agg.attributeCode == _categoryCode)
          for (final option in agg.options)
            if (option.count > 0 && option.count < state.totalCount) option,
    ]..sort((a, b) => b.count.compareTo(a.count));
    final selected = state.selectedFilters[_categoryCode] ?? const <String>{};

    void pickCategory(String? value) {
      final filters = {
        for (final e in state.selectedFilters.entries)
          if (e.key != _categoryCode) e.key: e.value,
        if (value != null) _categoryCode: {value},
      };
      controller.applyFilters(
        filters,
        priceFrom: state.priceFrom,
        priceTo: state.priceTo,
      );
    }

    return HubScaffold(
      currentTab: AppTab.home,
      appBar: HmTitleAppBar(title: brand.title, actions: actions),
      body: RefreshIndicator(
        color: AppColors.brandPrimary,
        onRefresh: controller.refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 600) controller.loadMore();
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 96,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.borderSubtle),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: HubImage(
                          url: brand.imageUrl,
                          fit: BoxFit.contain,
                          placeholder: (_) => const SizedBox.shrink(),
                          error: (_) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              brand.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.heading2.copyWith(color: AppColors.inkHeading),
                            ),
                            const SizedBox(height: 2),
                            if (products != null ||
                                !state.isLoading ||
                                state.totalCount > 0)
                              Text(
                                summary,
                                style: t.caption.copyWith(color: AppColors.inkMuted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (categories.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 12),
                  sliver: SliverToBoxAdapter(
                    child: HmChipRow(
                      chips: [
                        HmFilterChip(
                          label: l10n.brandsFilterAll,
                          selected: selected.isEmpty,
                          onTap: () => pickCategory(null),
                        ),
                        for (final c in categories)
                          HmFilterChip(
                            label: c.label,
                            selected: selected.contains(c.value),
                            onTap: () => pickCategory(
                              selected.contains(c.value) ? null : c.value,
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
                          l10n.hmProductCount(state.totalCount),
                          style: t.caption.copyWith(color: AppColors.inkMuted),
                        ),
                      ),
                      HmPillButton(
                        icon: Icons.swap_vert,
                        label: _sortLabel(l10n, state.sort),
                        onTap: () => _openSort(context, controller, state),
                      ),
                      const SizedBox(width: 8),
                      HmPillButton(
                        icon: Icons.tune,
                        label: l10n.filtersLabel,
                        onTap: () => _openFilters(context, ref, controller, state),
                      ),
                    ],
                  ),
                ),
              ),
              if (state.isLoading && state.products.isEmpty)
                const SliverToBoxAdapter(child: HmGridSkeleton())
              else if (state.error != null && state.products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: HmListError(
                    error: state.error!,
                    onRetry: controller.refresh,
                    emptyTitle: l10n.brandsEmpty,
                  ),
                )
              else if (state.products.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off,
                    title: l10n.brandsEmpty,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 173 / 283,
                    ),
                    itemCount: state.products.length,
                    itemBuilder: (context, i) => ProductCard(
                      product: state.products[i],
                      onTap: () => openProduct(context, state.products[i]),
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
      ),
    );
  }

  static String _sortLabel(AppLocalizations l10n, ProductSortField sort) =>
      switch (sort) {
        ProductSortField.relevance => l10n.sortRelevance,
        ProductSortField.priceAsc => l10n.sortPriceLowHigh,
        ProductSortField.priceDesc => l10n.sortPriceHighLow,
        ProductSortField.nameAsc => l10n.sortNameAz,
      };

  Future<void> _openSort(
    BuildContext context,
    BrandResultsController controller,
    PlpState state,
  ) async {
    final selected = await showModalBottomSheet<ProductSortField>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SortSheet(current: state.sort),
    );
    if (selected != null) controller.setSort(selected);
  }

  Future<void> _openFilters(
    BuildContext context,
    WidgetRef ref,
    BrandResultsController controller,
    PlpState state,
  ) async {
    final result = await showModalBottomSheet<FilterResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => FilterSheet(
        aggregations: state.aggregations,
        initial: state.selectedFilters,
        currency: ref.read(storeControllerProvider).currency,
        initialPriceFrom: state.priceFrom,
        initialPriceTo: state.priceTo,
        initialMinDiscount: state.minDiscount,
        initialMinRating: state.minRating,
      ),
    );
    if (result != null) {
      controller.applyFilters(
        result.attributes,
        priceFrom: result.priceFrom,
        priceTo: result.priceTo,
        minDiscount: result.minDiscount,
        minRating: result.minRating,
      );
    }
  }
}
