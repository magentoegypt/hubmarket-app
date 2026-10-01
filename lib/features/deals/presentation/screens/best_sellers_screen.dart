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
import '../best_sellers_controller.dart';
import '../widgets/hm_list_widgets.dart';
import '../widgets/list_states.dart';
import '../../../../app/theme/hub_icons.dart';

/// Best sellers (`hmBestSellers`): the store's products by units ordered,
/// ranked #1, #2, … in a two-column grid, the next page loading as the list
/// nears its end. Home's BEST_SELLERS "View all" and the no-results page's
/// "Popular right now" lead here, only with the Hub Market App; a server
/// without it answers "Cannot query field", which shows as an empty list.
class BestSellersScreen extends ConsumerWidget {
  const BestSellersScreen({super.key});

  static const IconData _icon = HubIcons.trophy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(bestSellersControllerProvider);
    final controller = ref.read(bestSellersControllerProvider.notifier);
    final error = state.error;

    final Widget body;
    if (state.isLoading && state.items.isEmpty) {
      body = const HmGridSkeleton();
    } else if (error != null && state.items.isEmpty) {
      body = HmListError(
        error: error,
        onRetry: controller.refresh,
        emptyTitle: l10n.bestSellersEmpty,
        emptyIcon: _icon,
      );
    } else if (state.items.isEmpty) {
      body = EmptyState(icon: _icon, title: l10n.bestSellersEmpty);
    } else {
      body = _BestSellersGrid(state: state, controller: controller);
    }

    return HubScaffold(
      currentTab: AppTab.home,
      appBar: HmTitleAppBar(title: l10n.bestSellersTitle),
      body: body,
    );
  }
}

class _BestSellersGrid extends StatelessWidget {
  const _BestSellersGrid({required this.state, required this.controller});

  final BestSellersState state;
  final BestSellersController controller;

  /// How close to the end the next page is asked for.
  static const double _loadAhead = 600;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final items = state.items;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical &&
            notification.metrics.extentAfter < _loadAhead) {
          controller.loadMore();
        }
        return false;
      },
      child: RefreshIndicator(
        color: AppColors.brandPrimary,
        onRefresh: controller.refresh,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              sliver: SliverToBoxAdapter(
                child: Text(
                  l10n.hmProductCount(state.totalCount),
                  style: t.caption.copyWith(color: AppColors.inkMuted),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverGrid.builder(
                gridDelegate: productGridDelegate(context),
                itemCount: items.length,
                itemBuilder: (context, i) => ProductCard(
                  product: items[i],
                  rank: i + 1,
                  onTap: () => openProduct(context, items[i]),
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
}
