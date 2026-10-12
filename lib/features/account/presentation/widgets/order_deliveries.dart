import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../domain/order.dart';
import '../order_format.dart';
import 'order_status_pill.dart';

/// The Unicode isolates that keep a number left to right inside Arabic text.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

/// A [StatusPill] in the tone of a delivery status [code], worded by the server
/// ([label]): green once it arrived, amber while it is held up, red when it
/// ended, blue for everything on its way (the website's "Delivery progress"
/// colours them the same four ways).
class DeliveryStatusPill extends StatelessWidget {
  const DeliveryStatusPill({
    super.key,
    required this.code,
    required this.label,
    this.verticalPadding = 3,
  });

  final String code;
  final String label;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) => switch (deliveryToneOf(code)) {
    DeliveryTone.success => StatusPill.success(
      label: label,
      verticalPadding: verticalPadding,
    ),
    DeliveryTone.warning => StatusPill.warning(
      label: label,
      verticalPadding: verticalPadding,
    ),
    DeliveryTone.danger => StatusPill.danger(
      label: label,
      verticalPadding: verticalPadding,
    ),
    DeliveryTone.info => StatusPill.info(
      label: label,
      verticalPadding: verticalPadding,
    ),
  };
}

/// The icon of a delivery status [code], for a status card.
IconData deliveryIconOf(String code) => switch (code) {
  'delivered' || 'completed' => HubIcons.circleCheck,
  'delayed' => HubIcons.clock,
  'on_hold' => HubIcons.circlePause,
  'canceled' || 'refunded' => HubIcons.circleX,
  'to_hub' || 'on_the_way' || 'shipped' => HubIcons.truck,
  'at_hub' => HubIcons.store,
  'preparing' || 'ready_for_pickup' => HubIcons.package,
  'ordered' => HubIcons.shoppingBag,
  _ => HubIcons.truck,
};

/// "Delivery progress" (FulfillmentTracking, CL036-DEV17): where the order's
/// parcels are, as the website's order page shows it — the overall status, then
/// each delivery with who sells and carries it, the lines it holds, its
/// courier and tracking number, the date the team expects it, and what has
/// happened to it so far.
///
/// Everything printed that names a status, a route or a courier is the
/// server's own wording in the store view's language (`status_label`,
/// `route_label`, `courier.label`), so a status never reads one way here and
/// another on the website; the app only chooses the colours.
///
/// Draws nothing for an order without deliveries (the server's `hm_fulfillment`
/// absent or empty): the screens then keep what they infer from invoices and
/// shipments.
class OrderDeliveries extends ConsumerWidget {
  const OrderDeliveries({super.key, required this.order, this.heading = true});

  final CustomerOrder order;

  /// The "Delivery progress" title with the overall status beside it, above the
  /// cards; false where the screen has a title and a status card of its own.
  final bool heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fulfillment = order.fulfillment;
    if (fulfillment == null || !fulfillment.hasDeliveries) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading) ...[
          // A wrap: "On the way to our warehouse" does not fit beside the title
          // on a narrow phone.
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.orderDeliveryProgress,
                style: t.title.copyWith(color: context.scaffoldHeading),
              ),
              DeliveryStatusPill(
                code: fulfillment.statusCode,
                label: fulfillment.statusLabel,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < fulfillment.deliveries.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _DeliveryCard(
            key: ValueKey('delivery-${fulfillment.deliveries[i].id}'),
            delivery: fulfillment.deliveries[i],
            order: order,
          ),
        ],
      ],
    );
  }
}

class _DeliveryCard extends ConsumerWidget {
  const _DeliveryCard({super.key, required this.delivery, required this.order});

  final OrderDelivery delivery;
  final CustomerOrder order;

  /// The order's lines this delivery carries, in the order's order.
  List<OrderLine> get _lines => [
    for (final line in order.lines)
      if (line.uid != null && delivery.itemUids.contains(line.uid)) line,
  ];

  Future<void> _open(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).errorGeneric;
    final opened = await ref.read(externalUriLauncherProvider)(uri);
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // The leg out of the warehouse can carry several sellers' items: no one
    // seller on it.
    final seller = delivery.route == 'from_hub' ? null : delivery.seller;
    final lines = _lines;
    final courier = delivery.courier;
    final expected = delivery.expectedDelivery;
    final trackingUrl = courier?.trackingUrl;
    final caption = [
      if (seller != null) l10n.orderDeliverySoldBy(seller.name),
      if (lines.isNotEmpty) l10n.orderItemCount(lines.length),
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (seller != null) ...[
                SellerLogo(seller: seller),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delivery.routeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.title.copyWith(color: context.scaffoldHeading),
                    ),
                    if (caption.isNotEmpty)
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption.copyWith(color: context.scaffoldMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Under the title, not beside it: the server's longer labels do not
          // fit a 150 px pill without being cut.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DeliveryStatusPill(
              code: delivery.statusCode,
              label: delivery.statusLabel,
            ),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final line in lines)
              Text(
                line.quantity > 1
                    ? '${line.name} × ${_quantity(line.quantity)}'
                    : line.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.body.copyWith(color: context.scaffoldHeading),
              ),
          ],
          if (courier != null) ...[
            const SizedBox(height: 12),
            _CourierRow(courier: courier),
          ],
          if (expected != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(HubIcons.clock, size: 16, color: context.scaffoldMuted),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.orderExpectedDelivery(
                      formatStamp(expected.toLocal(), 'd MMM yyyy', locale),
                    ),
                    style: t.caption.copyWith(color: context.scaffoldMuted),
                  ),
                ),
              ],
            ),
          ],
          if (delivery.timeline.isNotEmpty) ...[
            const SizedBox(height: 14),
            _DeliveryTimeline(steps: delivery.timeline, locale: locale),
          ],
          if (trackingUrl != null) ...[
            const SizedBox(height: 14),
            HubButton(
              label: l10n.orderTrackParcel,
              icon: HubIcons.truck,
              iconSize: 20,
              onPressed: () => _open(context, ref, trackingUrl),
            ),
          ],
        ],
      ),
    );
  }

  /// "2" for 2.0, "1.5" as it is.
  static String _quantity(double value) =>
      value == value.roundToDouble() ? '${value.round()}' : '$value';
}

/// Who carries it: the courier company (or "Seller's own delivery" /
/// "Hub Market delivery") and, for a courier, its tracking number — copyable.
class _CourierRow extends StatelessWidget {
  const _CourierRow({required this.courier});

  final DeliveryCourier courier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final number = courier.trackingNumber;
    return Row(
      children: [
        Icon(HubIcons.truck, size: 16, color: context.scaffoldMuted),
        const SizedBox(width: 8),
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: courier.title,
                  style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
                ),
                if (number != null)
                  TextSpan(
                    // A number reads left to right in Arabic too.
                    text: ' · $_lri$number$_pdi',
                    style: t.body.copyWith(color: context.scaffoldMuted),
                  ),
              ],
            ),
          ),
        ),
        if (number != null)
          Semantics(
            button: true,
            label: l10n.orderCopyTrackingNumber,
            excludeSemantics: true,
            child: Tooltip(
              message: l10n.orderCopyTrackingNumber,
              child: InkResponse(
                radius: 18,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final copied = l10n.orderTrackingCopied;
                  await Clipboard.setData(ClipboardData(text: number));
                  messenger.showSnackBar(SnackBar(content: Text(copied)));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    HubIcons.copy,
                    size: 16,
                    color: context.scaffoldMuted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// What has happened to a delivery, oldest first, ending on where it is now:
/// each step wears the colour of its own status (green done or arrived, amber
/// held up, red ended) and the one it stands on, blue while it moves. Nothing
/// ahead of it is drawn: the server records what happened, and the app does
/// not guess the rest.
class _DeliveryTimeline extends StatelessWidget {
  const _DeliveryTimeline({required this.steps, required this.locale});

  final List<DeliveryStep> steps;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            key: ValueKey('step-$i'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                child: Column(
                  children: [
                    _StepDot(
                      tone: steps[i].tone,
                      current: i == steps.length - 1,
                    ),
                    if (i != steps.length - 1)
                      Container(
                        width: 2,
                        height: 22,
                        color: AppColors.successStrong,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      steps[i].statusLabel,
                      style: (i == steps.length - 1 ? t.bodyStrong : t.body)
                          .copyWith(color: context.scaffoldHeading),
                    ),
                    if (steps[i].at != null)
                      Text(
                        orderFmtStepAt(steps[i].at!, locale),
                        style: t.caption.copyWith(color: context.scaffoldMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({required this.tone, required this.current});

  final DeliveryTone tone;

  /// The step the delivery stands on now.
  final bool current;

  @override
  Widget build(BuildContext context) {
    const Widget tick = Icon(HubIcons.check, size: 12, color: Colors.white);
    const Widget cross = Icon(HubIcons.x, size: 12, color: Colors.white);
    final Widget dot = Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
    // A step in the past is done (a tick) unless it recorded a delay, a hold
    // or an end: those keep their amber or red, as the website colours them.
    final (color, glyph) = switch (tone) {
      DeliveryTone.success => (AppColors.successStrong, tick),
      DeliveryTone.warning => (AppColors.warning, dot),
      DeliveryTone.danger => (AppColors.danger, cross),
      DeliveryTone.info =>
        current ? (AppColors.info, dot) : (AppColors.successStrong, tick),
    };
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: glyph,
    );
  }
}
