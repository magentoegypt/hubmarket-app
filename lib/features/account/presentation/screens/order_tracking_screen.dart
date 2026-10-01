import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/order.dart';
import '../order_format.dart';
import '../widgets/order_cancel_section.dart';
import '../widgets/order_packages.dart';
import '../../../../app/theme/hub_icons.dart';

/// One timeline step: a label, an optional timestamp, and whether it's done.
typedef _Step = ({String label, String time, bool done});

/// Track Order (Figma `63:2`): status banner, a four-stage timeline driven by
/// what the backend has actually done to the order (see [_stageIndex]), the
/// carrier + tracking number(s) once a shipment exists, delivery address,
/// items, and a help link. Reached from the My Orders "Track" action — and,
/// for a guest, straight from checkout — with the [CustomerOrder].
class OrderTrackingScreen extends ConsumerStatefulWidget {
  const OrderTrackingScreen({super.key, required this.order});

  final CustomerOrder order;

  @override
  ConsumerState<OrderTrackingScreen> createState() =>
      _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  /// Replaced by Magento's copy once the order is cancelled here.
  late CustomerOrder _order = widget.order;

  CustomerOrder get order => _order;

  /// Which of the 4 fixed stages the order has reached (0 = Placed …
  /// 3 = Delivered), read from what the backend has actually recorded rather
  /// than guessed from the status label:
  ///
  ///   0 Order Placed      the customer checked out
  ///   1 Order Confirmed   an invoice exists
  ///   2 Packed & Shipped  a shipment exists
  ///   3 Delivered         the order is complete
  ///
  /// Cancelled returns -1 and On Hold returns the stage genuinely reached —
  /// both are states an order sits in, not stages it passes through, so the
  /// timeline stops there and the status card names the state.
  ///
  /// Each stage implies the ones before it: Magento can invoice and ship in
  /// either order, and a shipment without an invoice still means the order got
  /// packed, so the timeline fills up to the furthest event rather than
  /// leaving a gap in the middle.
  int _stageIndex() {
    if (order.isCancelled) return -1;
    if (order.isDelivered) return 3;
    if (order.hasShipment || order.hasTracking) return 2;
    if (order.hasInvoice) return 1;
    return 0;
  }

  /// The four fixed timeline stages, filled up to (and including) the reached
  /// stage. Only "Order Placed" carries a timestamp (the order date).
  List<_Step> _steps(AppLocalizations l10n, String locale, String storeZone) {
    final labels = <String>[
      l10n.orderPlaced,
      l10n.orderStageConfirmed,
      l10n.orderStagePacked,
      l10n.ordersFilterDelivered,
    ];
    final reached = _stageIndex();
    return [
      for (var i = 0; i < labels.length; i++)
        (
          label: labels[i],
          time: i == 0 ? orderFmtDateTime(order.date, locale, storeZone) : '',
          // Placed always stands: the order exists, so it was placed — even
          // once cancelled (reached < 0), where the rest stay pending.
          done: i == 0 || i <= reached,
        ),
    ];
  }

  IconData _statusIcon() {
    if (order.isOnHold) return HubIcons.circlePause;
    return switch (_stageIndex()) {
      < 0 => HubIcons.circleX,
      3 => HubIcons.circleCheck,
      2 => HubIcons.truck,
      1 => HubIcons.receiptText,
      _ => HubIcons.shoppingBag,
    };
  }

  String _statusLabel(AppLocalizations l10n) {
    // Hold reads over the stage: the order is paused where it got to, and
    // saying "Order Confirmed" while it sits on hold would be misleading.
    if (order.isOnHold) return l10n.orderStatusOnHold;
    return switch (_stageIndex()) {
      < 0 => l10n.orderStatusCancelled,
      3 => l10n.ordersFilterDelivered,
      2 => l10n.orderStagePacked,
      1 => l10n.orderStageConfirmed,
      _ => l10n.orderPlaced,
    };
  }

  /// Secondary line under the status: the real delivery method when present,
  /// otherwise the order date. No fabricated per-order ETA.
  String _statusSub(String locale, String storeZone) =>
      (order.shippingMethod != null && order.shippingMethod!.isNotEmpty)
      ? order.shippingMethod!
      : orderFmtDateTime(order.date, locale, storeZone);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Empty until the store config lands — the timestamp then reads as it
    // always did (device-local) rather than jumping once it arrives.
    final storeZone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    final steps = _steps(l10n, locale, storeZone);
    // One package per store, as on the order detail (22): the server's own
    // split when HubApp has it, else the lines by seller; null keeps one list.
    final packages = orderPackageViews(order);
    // Numbers a package card shows are not listed again in Tracking.
    final packaged = packagedTrackingNumbers(packages);
    final looseTrackings = [
      for (final t in order.trackings)
        if (!packaged.contains(t.number)) t,
    ];
    final showTracking =
        looseTrackings.isNotEmpty || !anyPackageShipped(packages);

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: HubTopBar(title: l10n.trackOrderTitle),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Status card — current stage, delivery method, and order number.
          Container(
            width: double.infinity,
            color: AppColors.surfaceTint,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _statusIcon(),
                    color: AppColors.brandPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusLabel(l10n),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: AppColors.inkHeading,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _statusSub(locale, storeZone),
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        l10n.orderNumber(order.number),
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _Band(),

          // Order Status timeline.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
            child: Text(
              l10n.orderStatusTitle,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.inkHeading,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
            child: _Timeline(steps: steps),
          ),
          const _Band(),

          // Carrier + tracking number(s) — the whole point of this screen. Only
          // rendered once Magento has a shipment; no fabricated placeholder.
          // With per-store packages each card carries its own shipments.
          if (showTracking) ...[
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
              child: Text(
                l10n.orderTrackingSection,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.inkHeading,
                ),
              ),
            ),
            if (looseTrackings.isEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
                child: Text(
                  l10n.orderNoTracking,
                  style: const TextStyle(color: AppColors.inkMuted),
                ),
              )
            else
              for (final t in looseTrackings) _TrackingRow(tracking: t),
            const _Band(),
          ],

          // Delivery address.
          if (order.shippingAddress != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    HubIcons.mapPin,
                    color: AppColors.brandPrimary,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.orderDeliveryAddress,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.inkHeading,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [order.shippingName, order.shippingAddress]
                              .where((s) => s != null && s.isNotEmpty)
                              .join(' · '),
                          style: const TextStyle(color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (order.shippingAddress != null) const _Band(),

          // Items.
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
            child: Text(
              l10n.orderItemsCount(order.itemCount),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.inkHeading,
              ),
            ),
          ),
          // With HubApp, one package per store, as on the order detail (22).
          if (packages != null)
            // White cards on the page grey, as on the order detail (22).
            ColoredBox(
              color: groupedPageColor(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  children: [
                    for (var i = 0; i < packages.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      OrderPackageCard(
                        index: i + 1,
                        view: packages[i],
                        order: order,
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            )
          else
            for (final line in order.lines) _ItemRow(line: line, l10n: l10n),
          const SizedBox(height: 8),
          const _Band(),

          // Cancel order (Figma 21b) — a guest's lookup lands here (26), so
          // this is where a guest asks for a cancellation by e-mail.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OrderCancelSection(
              order: order,
              bordered: true,
              onCancelled: (updated) => setState(() => _order = updated),
            ),
          ),

          // Need help.
          InkWell(
            onTap: () => context.push(AppRoutes.help),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    HubIcons.headset,
                    size: 18,
                    color: AppColors.brandPrimary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.orderNeedHelp,
                    style: const TextStyle(
                      color: AppColors.brandPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
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

/// One shipment: carrier + service label, the AWB forced LTR (an Arabic layout
/// must not reverse a tracking number), and a copy action.
class _TrackingRow extends StatelessWidget {
  const _TrackingRow({required this.tracking});

  final OrderTracking tracking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = [
      tracking.carrier,
      tracking.title,
    ].where((s) => s.isNotEmpty).join(' \u00b7 ');
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
      leading: const Icon(
        HubIcons.truck,
        color: AppColors.brandPrimary,
      ),
      title: Text(label.isEmpty ? l10n.orderTrackingSection : label),
      subtitle: Text(
        tracking.number,
        textDirection: TextDirection.ltr,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      trailing: IconButton(
        icon: const Icon(HubIcons.copy),
        tooltip: l10n.orderTrackingSection,
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: tracking.number));
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(l10n.orderTrackingCopied)));
          }
        },
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});
  final List<_Step> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _Dot(done: steps[i].done),
                    if (i != steps.length - 1)
                      Expanded(
                        child: Container(
                          width: 2.5,
                          // Navy through completed segments; grey into a
                          // pending step.
                          color: steps[i + 1].done
                              ? AppColors.brandPrimary
                              : AppColors.borderDefault,
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].label,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: steps[i].done
                                ? AppColors.inkHeading
                                : AppColors.inkMuted,
                          ),
                        ),
                        if (steps[i].time.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            steps[i].time,
                            style: const TextStyle(
                              color: AppColors.inkMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: done ? AppColors.brandPrimary : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: done ? AppColors.brandPrimary : AppColors.borderDefault,
          width: 2,
        ),
      ),
      child: done
          ? const Icon(HubIcons.check, size: 13, color: Colors.white)
          : null,
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.line, required this.l10n});
  final OrderLine line;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Thumb(url: line.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkHeading,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.orderQty(line.quantity.toInt()),
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (line.price != null) ...[
            const SizedBox(width: 8),
            Text(
              line.price!.formatted(),
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.brandPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 52×52 rounded product thumbnail with a neutral placeholder.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 52,
        height: 52,
        child: HubImage(
          url: url,
          decodeWidth: 52,
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
