import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_chip.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/load_failure_view.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../returns/domain/returns.dart';
import '../../../returns/presentation/returns_providers.dart';
import '../../data/account_repository.dart';
import '../../domain/order.dart';
import '../guest_orders_controller.dart';
import '../order_actions.dart';
import '../widgets/order_list_card.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

/// Order status buckets for the filter chips (Figma 21), mapped from Magento's
/// free-text status — which varies by config — matched loosely on keywords.
/// [returns] keeps the orders the customer has returned something from.
enum _OrderFilter { all, inProgress, delivered, returns }

bool _statusMatches(
  _OrderFilter f,
  CustomerOrder o,
  Map<String, List<ReturnSummary>> returns,
) {
  return switch (f) {
    _OrderFilter.all => true,
    _OrderFilter.delivered => o.isDelivered,
    _OrderFilter.inProgress => !o.isDelivered && !o.isCancelled,
    _OrderFilter.returns => returns.containsKey(o.number),
  };
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  final ScrollController _scroll = ScrollController();
  _OrderFilter _filter = _OrderFilter.all;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 300) {
      ref.read(ordersControllerProvider.notifier).loadMore();
    }
  }

  Future<void> _reorder(CustomerOrder order) =>
      reorderOrder(context, ref, order);

  /// Choosing Returns needs every return the customer has, not the first page.
  Future<void> _setFilter(_OrderFilter filter) async {
    setState(() => _filter = filter);
    if (filter != _OrderFilter.returns) return;
    final notifier = ref.read(myReturnsControllerProvider.notifier);
    for (var i = 0; i < 20; i++) {
      final state = ref.read(myReturnsControllerProvider);
      if (state.isLoading || !state.hasMore) break;
      await notifier.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Guests have no `customer { orders }`: querying it without a bearer is a
    // hard 403 (`graphql-authorization`), which used to render an error page
    // whose Retry could never succeed. Resolve the orders this device
    // remembers through Magento's guest lookups instead.
    final isAuthenticated = ref.watch(authControllerProvider).isAuthenticated;

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: HubTopBar(title: l10n.ordersTitle),
      body: ColoredBox(
        color: groupedPageColor(context),
        child: isAuthenticated
            ? _customerBody(l10n, ref.watch(ordersControllerProvider))
            : _guestBody(l10n, ref.watch(guestOrdersControllerProvider)),
      ),
    );
  }

  Widget _card(
    CustomerOrder order, {
    Map<String, List<ReturnSummary>> returns = const {},
  }) {
    final own = returns[order.number] ?? const <ReturnSummary>[];
    return OrderListCard(
      order: order,
      returns: own,
      onOpen: () => context.push(AppRoutes.orderDetail, extra: order),
      onBuyAgain: () => _reorder(order),
      onRate: () => rateOrderItems(context, order),
      onOpenReturn: (open) => context.push(
        open.length == 1
            ? AppRoutes.returnDetail(open.single.id)
            : AppRoutes.returns,
      ),
    );
  }

  Widget _customerBody(AppLocalizations l10n, OrdersState state) {
    if (state.isLoading && state.orders.isEmpty) {
      return const _OrdersSkeleton();
    }
    if (state.error != null && state.orders.isEmpty) {
      // Offline: the S3 page, which reloads by itself once the network is back.
      return LoadFailureView(
        error: state.error,
        onRetry: ref.read(ordersControllerProvider.notifier).refresh,
      );
    }
    if (state.orders.isEmpty) {
      return EmptyState(
        icon: HubIcons.receiptText,
        title: l10n.ordersEmpty,
      );
    }
    // The customer's returns, by order: the Returns chip, each store's "Return
    // in progress" pill and "View return". Only while returns are on.
    final returnsOn = ref.watch(returnsAvailableProvider);
    final byOrder = <String, List<ReturnSummary>>{};
    if (returnsOn) {
      for (final r in ref.watch(myReturnsControllerProvider).items) {
        byOrder.putIfAbsent(r.orderNumber, () => []).add(r);
      }
    }
    final filter = returnsOn || _filter != _OrderFilter.returns
        ? _filter
        : _OrderFilter.all;
    final filtered = state.orders
        .where((o) => _statusMatches(filter, o, byOrder))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(
          current: filter,
          showReturns: returnsOn,
          onChanged: _setFilter,
        ),
        Expanded(
          child: filtered.isEmpty
              ? EmptyState(
                  icon: HubIcons.receiptText,
                  title: l10n.ordersEmpty,
                )
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    for (final o in filtered) ...[
                      _card(o, returns: byOrder),
                      const SizedBox(height: 12),
                    ],
                    if (state.isLoadingMore)
                      const Padding(
                        padding: EdgeInsets.all(4),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _guestBody(AppLocalizations l10n, GuestOrdersState state) {
    final notifier = ref.read(guestOrdersControllerProvider.notifier);
    if (state.isLoading && state.isEmpty) {
      return const _OrdersSkeleton();
    }
    // Nothing resolved at all: a transient failure worth retrying — unlike the
    // old guest path, this Retry can actually succeed.
    if (state.error != null && state.orders.isEmpty) {
      return LoadFailureView(error: state.error, onRetry: notifier.refresh);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        if (state.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 36, 8, 8),
            child: EmptyState(
              icon: HubIcons.truck,
              title: l10n.ordersGuestTitle,
              body: l10n.ordersGuestBody,
            ),
          )
        else ...[
          for (final o in state.orders) ...[
            _card(o),
            const SizedBox(height: 12),
          ],
          for (final entry in state.unresolved) ...[
            _UnresolvedRow(
              number: entry.number,
              onRetry: notifier.refresh,
              onRemove: () => notifier.forget(entry.number),
            ),
            const SizedBox(height: 12),
          ],
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.guestTrackOrder),
            icon: const Icon(HubIcons.search, size: 18),
            label: Text(l10n.ordersTrackAnother),
          ),
        ),
        TextButton(
          onPressed: () => context.push(AppRoutes.signIn),
          child: Text(l10n.ordersGuestSignIn),
        ),
      ],
    );
  }
}

/// A remembered guest order the backend didn't return this load. Kept visible
/// rather than silently dropped, so a network blip can't quietly delete the
/// only record the guest has of their order.
class _UnresolvedRow extends StatelessWidget {
  const _UnresolvedRow({
    required this.number,
    required this.onRetry,
    required this.onRemove,
  });

  final String number;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.ordersGuestUnresolved(number),
              style: t.caption.copyWith(color: AppColors.inkMuted),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
          TextButton(onPressed: onRemove, child: Text(l10n.ordersGuestRemove)),
        ],
      ),
    );
  }
}

/// The orders' first load: three cards shaped like [OrderListCard] — number,
/// date and total, a rule, two store rows and the actions — shimmering in place
/// of a spinner. White cards like the real ones.
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, {double height = 12}) =>
        SkeletonBox(width: width, height: height, borderRadius: 4);
    Widget row() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SkeletonBox.circle(size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 70, height: 14, borderRadius: 4),
                SizedBox(height: 6),
                SkeletonBox(width: 96, height: 20, borderRadius: 10),
              ],
            ),
          ),
          SizedBox(width: 10),
          SkeletonBox(width: 40, height: 40),
          SizedBox(width: 6),
          SkeletonBox(width: 40, height: 40),
        ],
      ),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: groupCardColor(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Shimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            bar(140, height: 16),
                            const SizedBox(height: 6),
                            bar(110),
                          ],
                        ),
                      ),
                      bar(52, height: 15),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.borderSubtle,
                  ),
                  row(),
                  if (i == 0) row(),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Expanded(child: SkeletonBox(height: 52, borderRadius: 12)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(height: 52, borderRadius: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Figma 21 "filters": a white strip of 36 px chips — All, In progress,
/// Delivered and, while returns are on, Returns — 4 px under the app bar, 12 px
/// above the cards.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.current,
    required this.showReturns,
    required this.onChanged,
  });

  final _OrderFilter current;
  final bool showReturns;
  final ValueChanged<_OrderFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <_OrderFilter, String>{
      _OrderFilter.all: l10n.ordersFilterAll,
      _OrderFilter.inProgress: l10n.ordersFilterInProgress,
      _OrderFilter.delivered: l10n.ordersFilterDelivered,
      if (showReturns) _OrderFilter.returns: l10n.ordersFilterReturns,
    };
    return Material(
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 12),
        child: Row(
          children: [
            for (final entry in labels.entries) ...[
              if (entry.key != labels.keys.first) const SizedBox(width: 8),
              HubChip(
                label: entry.value,
                selected: current == entry.key,
                onTap: () => onChanged(entry.key),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
