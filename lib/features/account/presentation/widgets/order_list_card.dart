import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/store_features.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../../returns/domain/returns.dart';
import '../../domain/order.dart';
import '../order_cancellation.dart';
import '../order_format.dart';
import 'order_cancel_section.dart';
import 'order_packages.dart';
import 'order_status_pill.dart';

/// Figma 21 "order/#…": one order of My orders — its number, date, item count
/// and total; one row per store (the store's logo and name, its own status and
/// its items' thumbnails); and the actions that fit where the order stands:
///
/// * in progress: View order, and Cancel order when the store allows it;
/// * delivered: Buy again and Rate items;
/// * cancelled: View order and Buy again;
/// * a return open on it: View return.
///
/// The whole card opens the order ([onOpen]). [returns] are the customer's
/// returns on this order (empty while returns are off).
class OrderListCard extends ConsumerWidget {
  const OrderListCard({
    super.key,
    required this.order,
    required this.onOpen,
    required this.onBuyAgain,
    required this.onRate,
    required this.onOpenReturn,
    this.returns = const <ReturnSummary>[],
  });

  final CustomerOrder order;
  final VoidCallback onOpen;
  final VoidCallback onBuyAgain;
  final VoidCallback onRate;

  /// The returns still open on the order (never empty); the list when there is
  /// more than one.
  final void Function(List<ReturnSummary> open) onOpenReturn;
  final List<ReturnSummary> returns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Magento stamps order dates in the store's zone — see orderFmtDate.
    final storeZone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    // Most orders don't offer CANCEL; don't read storeConfig for them.
    final features = order.offersCancel
        ? ref.watch(storeFeaturesProvider).valueOrNull ?? StoreFeatures.none
        : StoreFeatures.none;
    final openReturns = [
      for (final r in returns)
        if (r.state == ReturnState.open) r,
    ];
    final views =
        orderPackageViews(order) ?? [OrderPackageView(lines: order.lines)];
    final reorderable = order.lines.any((l) => (l.sku ?? '').isNotEmpty);
    final rateable = !order.placedAsGuest && reorderable;
    final cancellable = offersOrderCancel(features, order);

    Widget view() => HubButton(
      label: l10n.orderViewOrder,
      style: HubButtonStyle.outline,
      onPressed: onOpen,
    );

    final actions = <Widget>[
      if (openReturns.isNotEmpty)
        HubButton(
          label: l10n.orderViewReturn,
          style: HubButtonStyle.outline,
          onPressed: () => onOpenReturn(openReturns),
        )
      else if (order.isCancelled) ...[
        view(),
        if (reorderable)
          HubButton(
            label: l10n.orderBuyAgain,
            style: HubButtonStyle.ghost,
            onPressed: onBuyAgain,
          ),
      ] else if (order.isDelivered) ...[
        if (reorderable)
          HubButton(
            label: l10n.orderBuyAgain,
            style: HubButtonStyle.outline,
            onPressed: onBuyAgain,
          )
        else
          view(),
        if (rateable)
          HubButton(
            label: l10n.orderRateItems,
            style: HubButtonStyle.ghost,
            onPressed: onRate,
          ),
      ] else ...[
        view(),
        if (cancellable)
          HubButton(
            label: l10n.orderCancelAction,
            style: HubButtonStyle.danger,
            onPressed: () => startOrderCancel(
              context,
              order: order,
              reasons: features.cancellationReasons,
            ),
          ),
      ],
    ];

    return Material(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.orderNumber(order.number),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.title.copyWith(
                            color: context.scaffoldHeading,
                          ),
                        ),
                        Text(
                          '${orderFmtDate(order.date, locale, storeZone)} · '
                          '${l10n.orderItemCount(order.itemCount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(
                            color: context.scaffoldMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (order.total case final total?) ...[
                    const SizedBox(width: 8),
                    Text(
                      total.formatted(),
                      textDirection: TextDirection.ltr,
                      style: t.price.copyWith(color: context.scaffoldHeading),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Divider(
                height: 1,
                thickness: 1,
                color: context.isDarkMode
                    ? Colors.white12
                    : AppColors.borderSubtle,
              ),
              const SizedBox(height: 4),
              for (final view in views) ...[
                _PackageRow(
                  view: view,
                  pill: _pillFor(l10n, view, openReturns),
                ),
                const SizedBox(height: 4),
              ],
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// A store's status pill: "Return in progress" while a return is open with
  /// that store (with any, for an order the server did not split by store),
  /// else the store's own status, else the order's.
  Widget _pillFor(
    AppLocalizations l10n,
    OrderPackageView view,
    List<ReturnSummary> openReturns,
  ) {
    final returnOpen = view.package == null && view.seller == null
        ? openReturns.isNotEmpty
        : openReturns.any(
            (r) => returnSellerKey(r.seller) == returnSellerKey(view.seller),
          );
    if (returnOpen) {
      return StatusPill.returns(label: l10n.orderReturnInProgress);
    }
    final package = view.package;
    if (package != null && package.statusLabel.trim().isNotEmpty) {
      return OrderPackageStatusPill(package: package);
    }
    return OrderStatusPill(order: order);
  }
}

/// One store's row: logo, name and status on the left, the store's items'
/// thumbnails on the right (Figma "package", 64 px high).
class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.view, required this.pill});

  final OrderPackageView view;
  final Widget pill;

  /// The frames show at most three tiles; a fourth item turns the third tile
  /// into the count of what is left.
  static const int _tiles = 3;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final seller = view.seller;
    final lines = view.lines;
    final overflow = lines.length > _tiles;
    final shown = overflow ? _tiles - 1 : lines.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (seller != null) ...[
            SellerLogo(seller: seller),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (seller != null) ...[
                  Text(
                    seller.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyStrong.copyWith(
                      color: context.scaffoldHeading,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                pill,
              ],
            ),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(width: 10),
            for (var i = 0; i < shown; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              _Tile(child: _ThumbImage(url: lines[i].imageUrl)),
            ],
            if (overflow) ...[
              const SizedBox(width: 6),
              _Tile(
                child: Center(
                  child: Text(
                    '+${lines.length - shown}',
                    textDirection: TextDirection.ltr,
                    style: t.captionStrong.copyWith(color: AppColors.inkSubtle),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A 40 px thumbnail tile: radius 8 on the page grey.
class _Tile extends StatelessWidget {
  const _Tile({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 40,
      height: 40,
      child: ColoredBox(
        color: context.isDarkMode ? Colors.white10 : AppColors.surfaceSubtle,
        child: child,
      ),
    ),
  );
}

class _ThumbImage extends StatelessWidget {
  const _ThumbImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) => HubImage(
    url: url,
    width: 40,
    height: 40,
    placeholder: (_) => const SizedBox.shrink(),
    error: (_) => const SizedBox.shrink(),
  );
}
