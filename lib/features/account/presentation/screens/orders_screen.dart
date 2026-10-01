import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/load_failure_view.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/account_repository.dart';
import '../guest_orders_controller.dart';
import '../order_actions.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../domain/order.dart';
import '../order_format.dart';
import '../../../../app/theme/hub_icons.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

/// Order status buckets for the filter tabs (Figma). Mapped from Magento's
/// free-text status, which varies by config — matched loosely on keywords.
enum _OrderFilter { all, toReceive, delivered, cancelled }

bool _statusMatches(_OrderFilter f, CustomerOrder o) {
  return switch (f) {
    _OrderFilter.all => true,
    _OrderFilter.delivered => o.isDelivered,
    _OrderFilter.cancelled => o.isCancelled,
    _OrderFilter.toReceive => !o.isDelivered && !o.isCancelled,
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
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(l10n.accountOrders),
      ),
      body: isAuthenticated
          ? _customerBody(l10n, ref.watch(ordersControllerProvider))
          : _guestBody(l10n, ref.watch(guestOrdersControllerProvider)),
    );
  }

  Widget _card(CustomerOrder order) => _OrderCard(
    order: order,
    onDetails: () => context.push(AppRoutes.orderDetail, extra: order),
    onTrack: () => context.push(AppRoutes.orderTracking, extra: order),
    onReorder: () => _reorder(order),
  );

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
    final filtered = state.orders
        .where((o) => _statusMatches(_filter, o))
        .toList();
    return ListView(
      controller: _scroll,
      padding: EdgeInsets.zero,
      children: [
        _FilterBar(
          current: _filter,
          onChanged: (f) => setState(() => _filter = f),
        ),
        const _Band(),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: EmptyState(
              icon: HubIcons.receiptText,
              title: l10n.ordersEmpty,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(children: [for (final o in filtered) _card(o)]),
          ),
        if (state.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
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
      padding: EdgeInsets.zero,
      children: [
        if (state.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 8),
            child: EmptyState(
              icon: HubIcons.truck,
              title: l10n.ordersGuestTitle,
              body: l10n.ordersGuestBody,
            ),
          )
        else ...[
          const _Band(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                for (final o in state.orders) _card(o),
                for (final entry in state.unresolved)
                  _UnresolvedRow(
                    number: entry.number,
                    onRetry: notifier.refresh,
                    onRemove: () => notifier.forget(entry.number),
                  ),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
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
          ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l10n.ordersGuestUnresolved(number),
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
          TextButton(onPressed: onRemove, child: Text(l10n.ordersGuestRemove)),
        ],
      ),
    );
  }
}

/// 8px light section separator (Figma).
class _Band extends StatelessWidget {
  const _Band();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 8,
    child: ColoredBox(color: AppColors.surfaceMuted),
  );
}

/// The orders' first load: three cards shaped like [_OrderCard] — number and
/// date, a line, the total and the two actions — shimmering in place of a
/// spinner. White cards like the real ones, in both themes.
class _OrdersSkeleton extends StatelessWidget {
  const _OrdersSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget part(double factor, {double height = 12}) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: factor,
      child: SkeletonBox(height: height, borderRadius: 4),
    );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderDefault),
            ),
            child: Shimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            part(0.45, height: 14),
                            const SizedBox(height: 6),
                            part(0.6),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SkeletonBox(width: 72, height: 22, borderRadius: 11),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const SkeletonBox(width: 48, height: 48),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            part(0.85),
                            const SizedBox(height: 6),
                            part(0.3),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      SkeletonBox(width: 40, height: 11, borderRadius: 4),
                      Spacer(),
                      SkeletonBox(width: 84, height: 15, borderRadius: 4),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Expanded(child: SkeletonBox(height: 36, borderRadius: 18)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(height: 36, borderRadius: 18)),
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

/// Horizontal status filter pills (All / To Receive / Delivered / Cancelled).
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.current, required this.onChanged});
  final _OrderFilter current;
  final ValueChanged<_OrderFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = <_OrderFilter, String>{
      _OrderFilter.all: l10n.ordersFilterAll,
      _OrderFilter.toReceive: l10n.ordersFilterToReceive,
      _OrderFilter.delivered: l10n.ordersFilterDelivered,
      _OrderFilter.cancelled: l10n.ordersFilterCancelled,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          for (final entry in labels.entries) ...[
            _Chip(
              label: entry.value,
              selected: current == entry.key,
              onTap: () => onChanged(entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandPrimary : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: selected ? null : Border.all(color: AppColors.borderDefault),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({
    required this.order,
    required this.onDetails,
    required this.onTrack,
    required this.onReorder,
  });

  final CustomerOrder order;
  final VoidCallback onDetails;
  final VoidCallback onTrack;
  final VoidCallback onReorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Magento stamps order dates in the store's zone — see orderFmtDate.
    final storeZone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    final isPast = order.isDelivered || order.isCancelled;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.orderDetail, extra: order),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: number + date·items, status pill.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${order.number}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.inkHeading,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${orderFmtDate(order.date, Localizations.localeOf(context).languageCode, storeZone)} · ${l10n.orderItemCount(order.itemCount)}',
                          style: const TextStyle(
                            color: AppColors.inkMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusPill(order: order),
                ],
              ),
              if (order.lines.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final line in order.lines) _LineRow(line: line),
              ],
              const SizedBox(height: 2),
              const Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
              const SizedBox(height: 12),
              // Total.
              Row(
                children: [
                  Text(
                    l10n.orderTotalLabel,
                    style: const TextStyle(
                      color: AppColors.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  if (order.total != null)
                    Text(
                      order.total!.formatted(),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.brandPrimary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Actions: View Details + (Track in progress / Reorder past).
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: l10n.orderViewDetails,
                      onTap: onDetails,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: isPast ? l10n.orderReorder : l10n.orderTrack,
                      onTap: isPast ? onReorder : onTrack,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Solid status pill: gold = delivered, grey = cancelled, navy = in progress.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.order});
  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final cancelled = order.isCancelled;
    final color = order.isDelivered
        ? AppColors.accentGold
        : cancelled
        ? AppColors.inkMuted
        : AppColors.brandPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: cancelled ? AppColors.surfaceMuted : color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        order.status,
        style: TextStyle(
          color: cancelled ? AppColors.inkMuted : Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Outlined navy action pill (Track / Reorder).
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.brandPrimary),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.brandPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// One order line as a single row — thumbnail + product name + quantity —
/// matching the website order summary (QA: image, name and qty must sit on the
/// same line per item, not stacked as image-row-then-text-row). RTL-safe: the
/// Row mirrors so the thumbnail leads on the right in Arabic.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line});
  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Thumb(url: line.imageUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.3,
                    color: AppColors.inkHeading,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.orderQty(line.quantity.toInt()),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: HubImage(
          url: url,
          decodeWidth: 48,
          placeholder: (_) => const ColoredBox(color: AppColors.surfaceTint),
          error: (_) => const ColoredBox(
            color: AppColors.surfaceTint,
            child: Icon(
              HubIcons.image,
              size: 18,
              color: AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
