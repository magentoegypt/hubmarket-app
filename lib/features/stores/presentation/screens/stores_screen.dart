import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/category.dart';
import '../../../catalog/presentation/search_providers.dart';
import '../../../catalog/presentation/widgets/search_style.dart';
import '../../../catalog/presentation/widgets/sort_sheet.dart';
import '../../domain/store.dart';
import '../store_list_controller.dart';
import '../stores_providers.dart';
import '../widgets/store_widgets.dart';
import '../widgets/stores_unavailable.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../app/theme/hub_icons.dart';

/// The sellers of Hub Market (Figma 12): a store search, top-level category
/// chips, the featured seller's banner, then every approved seller with the
/// chosen sort, paging on scroll. Everything comes from `hmStores`.
///
/// While the server lists the `vendors` capability ([storeExtrasProvider]),
/// the chips are `hmStoreCategories`' — each with how many sellers it holds,
/// categories without any left out — and each card names the seller's
/// primary category ("Furniture · 38 products"). Without it: Home's
/// top-level categories and the product count alone.
class StoresScreen extends ConsumerStatefulWidget {
  const StoresScreen({super.key});

  @override
  ConsumerState<StoresScreen> createState() => _StoresScreenState();
}

class _StoresScreenState extends ConsumerState<StoresScreen> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  Timer? _debounce;

  /// What the store search asks for, once typing pauses.
  String _name = '';

  /// The top-level category the list is narrowed to; null for all.
  String? _categoryUid;

  /// The frame opens on "Top rated".
  StoreSort _sort = StoreSort.topRated;

  static const Duration _debounceDelay = Duration(milliseconds: 350);

  int? get _categoryId {
    final uid = _categoryUid;
    return uid == null ? null : int.tryParse(categoryIdFromUid(uid) ?? '');
  }

  StoreListQuery get _query =>
      StoreListQuery(categoryId: _categoryId, name: _name, sort: _sort);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
      ref.read(storeListControllerProvider(_query).notifier).loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (mounted) setState(() => _name = value.trim());
    });
    // The clear button follows the text at once.
    setState(() {});
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    setState(() => _name = '');
  }

  void _pickCategory(String? uid) {
    if (uid == _categoryUid) return;
    setState(() => _categoryUid = uid);
    _toTop();
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _pickSort() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showHubBottomSheet<StoreSort>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => SortChoiceSheet<StoreSort>(
        current: _sort,
        choices: [
          for (final sort in StoreSort.values)
            (value: sort, label: storeSortLabel(l10n, sort)),
        ],
      ),
    );
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    _toTop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(storesAvailableProvider);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return HubScaffold(
      currentTab: AppTab.home,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: canPop ? const HubBackButton() : null,
        centerTitle: false,
        titleSpacing: canPop ? 0 : 16,
        title: Text(
          l10n.storesTitle,
          style: TextStyle(
            fontSize: 18,
            height: 24 / 18,
            fontWeight: FontWeight.w700,
            color: context.scaffoldHeading,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(HubIcons.search, size: 22),
            tooltip: l10n.navSearch,
            onPressed: () => context.push(AppRoutes.search),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: available ? _body(context, l10n) : const StoresUnavailable(),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final query = _query;
    final list = ref.watch(storeListControllerProvider(query));
    // The banner stands for the chosen category; a name search shows only
    // its matches.
    final featured = _name.isEmpty
        ? ref.watch(featuredStoreProvider(_categoryId)).valueOrNull
        : null;
    // The chips: the seller API's, with their seller counts, while the
    // server lists them; otherwise (and until they load) the top-level
    // categories Home's "Shop by category" shows.
    final counted = ref.watch(storeExtrasProvider)
        ? ref.watch(storeCategoryChipsProvider).valueOrNull
        : null;
    final chips = counted != null && counted.items.isNotEmpty
        ? [
            for (final c in counted.items)
              (uid: c.uid, name: c.name, count: c.count as int?),
          ]
        : [
            for (final c
                in ref.watch(searchCategoryChoicesProvider).valueOrNull ??
                    const <Category>[])
              (uid: c.uid, name: c.name, count: null as int?),
          ];
    final allCount = counted != null && counted.items.isNotEmpty
        ? counted.totalCount
        : null;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(featuredStoreProvider(_categoryId));
        await ref.read(storeListControllerProvider(query).notifier).refresh();
      },
      child: CustomScrollView(
        controller: _scroll,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _SearchField(
                controller: _search,
                hint: l10n.storesSearchHint,
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
              ),
            ),
          ),
          if (chips.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.only(top: 16),
              sliver: SliverToBoxAdapter(
                child: _CategoryChips(
                  chips: chips,
                  allCount: allCount,
                  selectedUid: _categoryUid,
                  onPick: _pickCategory,
                ),
              ),
            ),
          if (featured != null)
            SliverPadding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
              sliver: SliverToBoxAdapter(
                child: FeaturedStoreBanner(
                  profile: featured,
                  onTap: () => openStore(context, featured.card),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _ListHeading(
                title: l10n.storesAllTitle,
                sortLabel: storeSortLabel(l10n, _sort),
                onSort: _pickSort,
              ),
            ),
          ),
          ..._list(context, l10n, list),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
      ),
    );
  }

  List<Widget> _list(
    BuildContext context,
    AppLocalizations l10n,
    StoreListState list,
  ) {
    if (list.isLoading && list.items.isEmpty) {
      return [
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 0),
          sliver: SliverList.separated(
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, __) => const StoreListTileSkeleton(),
          ),
        ),
      ];
    }
    final error = list.error;
    // The seller API isn't on this server after all.
    if (error is HubAppMissing) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: StoresUnavailable()),
      ];
    }
    if (error != null && list.items.isEmpty) {
      final retry = ref
          .read(storeListControllerProvider(_query).notifier)
          .refresh;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: isNetworkFailure(error) || ref.watch(isOfflineProvider)
              ? OfflineState(onRetry: retry)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error is Failure
                              ? failureMessage(context, error)
                              : l10n.errorGeneric,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: retry,
                          child: Text(l10n.actionRetry),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ];
    }
    if (list.items.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            icon: HubIcons.store,
            title: l10n.storesEmpty,
            body: _name.isEmpty
                ? null
                : l10n.storesNoMatch(isolateQuery(_name)),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 0),
        sliver: SliverList.separated(
          itemCount: list.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final store = list.items[i];
            return StoreListTile(
              store: store,
              detail: storeCardDetail(
                store,
                l10n.categoryProductCount(store.productCount),
              ),
              onTap: () => openStore(context, store),
            );
          },
        ),
      ),
      if (list.isLoadingMore)
        const SliverPadding(
          padding: EdgeInsetsDirectional.fromSTEB(16, 10, 16, 0),
          sliver: SliverToBoxAdapter(child: StoreListTileSkeleton()),
        ),
    ];
  }
}

/// A sort's name as the Stores list's sort action and sheet show it.
String storeSortLabel(AppLocalizations l10n, StoreSort sort) => switch (sort) {
  StoreSort.featured => l10n.sortFeatured,
  StoreSort.topRated => l10n.storesSortTopRated,
  StoreSort.newest => l10n.storesSortNewest,
  StoreSort.name => l10n.sortNameAz,
  StoreSort.productCount => l10n.storesSortMostProducts,
};

/// "Search stores": a filled 44 pt field with a clear button once typed in.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: TextStyle(
        fontSize: 14,
        height: 20 / 14,
        color: context.scaffoldHeading,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          color: context.scaffoldMuted,
        ),
        filled: true,
        fillColor: SearchStyle.pillFill(context),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        prefixIcon: Icon(HubIcons.search, size: 18, color: context.scaffoldMuted),
        prefixIconConstraints: const BoxConstraints(minWidth: 42),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(HubIcons.x, size: 18),
                color: context.scaffoldMuted,
                tooltip: l10n.searchClearField,
                onPressed: onClear,
              ),
      ),
    );
  }
}

/// "All · Grocery · Furniture · …": the top-level categories as 36 pt pills,
/// the chosen one navy, each with its seller count when the list has them.
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.chips,
    required this.selectedUid,
    required this.onPick,
    this.allCount,
  });

  final List<({String uid, String name, int? count})> chips;

  /// Sellers in all categories: the All chip's count, when known.
  final int? allCount;
  final String? selectedUid;
  final ValueChanged<String?> onPick;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final chip = i == 0 ? null : chips[i - 1];
          final label = chip?.name ?? l10n.filterAll;
          final count = chip == null ? allCount : chip.count;
          return StorePill(
            label: label,
            count: count,
            semanticLabel: count == null
                ? null
                : l10n.storesCategoryChip(label, count),
            selected: chip?.uid == selectedUid,
            onTap: () => onPick(chip?.uid),
          );
        },
      ),
    );
  }
}

/// "All stores" with the sort action (⇅ Top rated).
class _ListHeading extends StatelessWidget {
  const _ListHeading({
    required this.title,
    required this.sortLabel,
    required this.onSort,
  });

  final String title;
  final String sortLabel;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final color = context.scaffoldHeading;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              height: 24 / 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        InkWell(
          onTap: onSort,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(HubIcons.arrowUpDown, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  sortLabel,
                  style: TextStyle(
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The featured seller (Figma 12 "featured-store"): the store page's banner
/// photo — the brand navy without one — under a navy scrim, the FEATURED
/// STORE pill, the logo, name, rating and product count, and Visit.
///
/// The scrim darkens towards the bottom, where the text sits, so any seller's
/// banner stays legible (the frame's photo is dark at the top instead).
class FeaturedStoreBanner extends StatelessWidget {
  const FeaturedStoreBanner({
    super.key,
    required this.profile,
    required this.onTap,
  });

  final StoreProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final store = profile.card;
    final banner = profile.bannerUrl ?? '';
    final products = l10n.categoryProductCount(store.productCount);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 170,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banner.isEmpty)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.topStart,
                    end: AlignmentDirectional.bottomEnd,
                    colors: [AppColors.brandPrimary, Color(0xFF1E3A6E)],
                  ),
                ),
              )
            else
              HubImage(url: banner, fit: BoxFit.cover, shimmer: true),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1A0F2144), Color(0xE60F2144)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.storesFeaturedBadge,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 14 / 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      StoreLogo(
                        store: store,
                        size: 56,
                        borderWidth: 3,
                        borderColor: Colors.white,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            StoreNameLine(
                              name: store.name,
                              markColor: AppColors.accentOnDark,
                              style: const TextStyle(
                                fontSize: 18,
                                height: 24 / 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // "Furniture · ★ 4.8 · 38 products"
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (store.categoryName case final category?)
                                    TextSpan(text: '$category · '),
                                  if (store.isRated) ...[
                                    ratingSpan(
                                      store.rating!,
                                      size: 12,
                                      color: AppColors.borderStrong,
                                      starFirst: true,
                                    ),
                                    const TextSpan(text: ' · '),
                                  ],
                                  TextSpan(text: products),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 16 / 12,
                                color: AppColors.borderStrong,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          l10n.storesVisit,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 16 / 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkHeading,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: onTap),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
