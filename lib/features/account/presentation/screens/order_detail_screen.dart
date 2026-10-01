import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/hub_top_bar.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../../returns/presentation/widgets/return_items_button.dart';
import '../../../store_credit/presentation/store_credit_providers.dart';
import '../../domain/order.dart';
import '../order_actions.dart';
import '../order_format.dart';
import '../widgets/order_cancel_section.dart';
import '../widgets/order_packages.dart';
import '../widgets/order_status_pill.dart';

/// Full detail for a single placed order, navigated to with the [CustomerOrder]
/// via go_router `extra` (the list already holds every field, so no extra
/// query): when it was placed, one card per store with its own timeline, items
/// and actions, where it goes, what it cost and how it was paid, and "Cancel
/// order" when the store and the order allow it (Figma 22 / 21b).
///
/// Not drawn, because the backend has nothing behind them: the invoice and
/// shipment documents of the frame's "Documents" card (and "Download invoice"
/// beside the date), "Print order", and the delivery estimate of each package.
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({super.key, required this.order});

  final CustomerOrder order;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  /// Replaced by Magento's copy once the order is cancelled here.
  late CustomerOrder _order = widget.order;

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Magento stamps order times in the store's zone — see orderFmtDate.
    final storeZone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    // Figma 22: one package per store — the server's own split when HubApp
    // has it, else the lines by seller; null keeps one list.
    final packages = orderPackageViews(order);
    // Numbers a package card shows are not listed again below.
    final packaged = packagedTrackingNumbers(packages);
    final looseTrackings = [
      for (final tracking in order.trackings)
        if (!packaged.contains(tracking.number)) tracking,
    ];
    // Before a package ships its timeline says so; an order the server did not
    // split keeps the note where the numbers will appear.
    final showTracking =
        looseTrackings.isNotEmpty || (packages == null && !order.hasShipment);
    final reorderable = order.lines.any((l) => (l.sku ?? '').isNotEmpty);
    final billingDiffers =
        (order.billingAddress ?? '').isNotEmpty &&
        (order.billingAddress != order.shippingAddress ||
            order.billingName != order.shippingName);

    final sections = <Widget>[
      Text(
        l10n.orderPlacedOn(orderFmtPlaced(order.date, locale, storeZone)),
        style: t.caption.copyWith(color: context.scaffoldMuted),
      ),
      if (packages != null)
        for (var i = 0; i < packages.length; i++)
          OrderPackageCard(index: i + 1, view: packages[i], order: order)
      else
        OrderPackageCard(
          index: 1,
          order: order,
          view: OrderPackageView(lines: order.lines),
          title: l10n.orderItemsSection,
          statusPill: OrderStatusPill(order: order),
        ),
      if (showTracking) _TrackingCard(trackings: looseTrackings),
      if ((order.shippingAddress ?? '').isNotEmpty)
        _AddressCard(
          title: (order.shippingName ?? '').isNotEmpty
              ? l10n.orderDeliveringTo(order.shippingName!)
              : l10n.orderDeliveryAddress,
          address: order.shippingAddress!,
          icon: HubIcons.mapPin,
        ),
      if (billingDiffers)
        _AddressCard(
          title: l10n.orderBillingAddress,
          subtitle: order.billingName,
          address: order.billingAddress!,
          icon: HubIcons.creditCard,
        ),
      _PaymentCard(order: order),
      if (packages == null && order.comments.isNotEmpty)
        _TimelineCard(order: order, locale: locale, storeZone: storeZone),
      // Their own spacing: either may be out (nothing returnable, not
      // cancellable) and leave no gap.
      _NoGap(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Re-adds every line to the cart (QA request for this page).
            if ((order.isDelivered || order.isCancelled) && reorderable)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: HubButton(
                  label: l10n.orderBuyAgain,
                  style: HubButtonStyle.outline,
                  onPressed: () => reorderOrder(context, ref, order),
                ),
              ),
            // Return items (Figma 22), when the order has something returnable.
            ReturnItemsButton(order: order),
          ],
        ),
      ),
      _NoGap(
        OrderCancelSection(
          order: order,
          onCancelled: (updated) => setState(() => _order = updated),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: groupedPageColor(context),
      appBar: HubTopBar(
        title: l10n.orderNumber(order.number),
        actions: [
          HubIconButton(
            icon: HubIcons.circleHelp,
            tooltip: l10n.accountHelp,
            onPressed: () => context.push(AppRoutes.help),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0 && sections[i] is! _NoGap) const SizedBox(height: 12),
            sections[i],
          ],
        ],
      ),
    );
  }
}

/// A section that brings its own spacing (or none), so the page's 12 px
/// gap is not added above it.
class _NoGap extends StatelessWidget {
  const _NoGap(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A white card of the page: radius 16 and 14 px inside.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: groupCardColor(context),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

/// Figma 22 "address": a pin, "Delivering to Sara Ahmed" and the address
/// under it.
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.title,
    required this.address,
    required this.icon,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String address;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return _Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.accentStrong),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
                ),
                const SizedBox(height: 2),
                if ((subtitle ?? '').isNotEmpty)
                  Text(
                    subtitle!,
                    style: t.caption.copyWith(color: context.scaffoldMuted),
                  ),
                Text(
                  address,
                  style: t.caption.copyWith(color: context.scaffoldMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Figma 22 "payment-summary": Payment, the subtotal, discount and delivery,
/// store credit, and how it was paid beside the total.
class _PaymentCard extends ConsumerWidget {
  const _PaymentCard({required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final quantity = order.lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity.toInt(),
    );
    final method = order.paymentMethodName?.trim() ?? '';
    // Store credit the order used (HubAppAccount); customers only.
    final credit = order.placedAsGuest
        ? null
        : ref.watch(orderStoreCreditProvider(order.number)).valueOrNull;
    final discountLabel = (order.discountLabel ?? '').isNotEmpty
        ? '${l10n.cartDiscount} (${order.discountLabel})'
        : l10n.cartDiscount;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.orderPaymentTitle,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          if (order.subtotal != null)
            _PayRow(
              label: l10n.orderSubtotalItems(quantity),
              amount: order.subtotal!,
            ),
          if (order.discount != null)
            _PayRow(label: discountLabel, amount: order.discount!, minus: true),
          if (order.shippingAmount != null)
            _PayRow(
              label: l10n.orderDeliveryLabel,
              amount: order.shippingAmount!,
            ),
          if (credit != null)
            _PayRow(
              label: l10n.checkoutStoreCredit,
              amount: credit,
              minus: true,
            ),
          if (order.total != null)
            _PayRow(
              label: method.isEmpty
                  ? l10n.cartTotal
                  : (order.hasInvoice ? l10n.orderPaidWith(method) : method),
              amount: order.total!,
              strong: true,
            ),
        ],
      ),
    );
  }
}

/// A line of the payment card: the label in subtle ink, the amount in Body
/// Strong — the last row's label Body Strong and its amount Price.
class _PayRow extends StatelessWidget {
  const _PayRow({
    required this.label,
    required this.amount,
    this.minus = false,
    this.strong = false,
  });

  final String label;
  final Money amount;

  /// The amount is a reduction: `−AED 25`.
  final bool minus;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final ink = context.scaffoldHeading;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: strong
                  ? t.bodyStrong.copyWith(color: ink)
                  : t.body.copyWith(color: context.isDarkMode
                        ? context.scaffoldMuted
                        : AppColors.inkSubtle),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            minus ? '−${amount.formatted()}' : amount.formatted(),
            textDirection: TextDirection.ltr,
            style: (strong ? t.price : t.bodyStrong).copyWith(color: ink),
          ),
        ],
      ),
    );
  }
}

/// Shipments of an order the server did not split by store (and the numbers no
/// package shows): the carrier and number with a copy action, or the note
/// that they appear once the order ships.
class _TrackingCard extends StatelessWidget {
  const _TrackingCard({required this.trackings});

  final List<OrderTracking> trackings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.orderTrackingSection,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          if (trackings.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.orderNoTracking,
                style: t.body.copyWith(color: context.scaffoldMuted),
              ),
            )
          else
            for (final tracking in trackings)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(
                      HubIcons.truck,
                      size: 20,
                      color: AppColors.brandPrimary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            [tracking.carrier, tracking.title]
                                .where((s) => s.isNotEmpty)
                                .join(' · '),
                            style: t.caption.copyWith(
                              color: context.scaffoldMuted,
                            ),
                          ),
                          Text(
                            tracking.number,
                            textDirection: TextDirection.ltr,
                            style: t.bodyStrong.copyWith(
                              color: context.scaffoldHeading,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(HubIcons.copy, size: 20),
                      tooltip: l10n.orderCopyTrackingNumber,
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final copied = l10n.orderTrackingCopied;
                        await Clipboard.setData(
                          ClipboardData(text: tracking.number),
                        );
                        messenger.showSnackBar(
                          SnackBar(content: Text(copied)),
                        );
                      },
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// The order's status history (an order the server did not split), newest
/// first: a dot, the message, and its time.
class _TimelineCard extends StatelessWidget {
  const _TimelineCard({
    required this.order,
    required this.locale,
    required this.storeZone,
  });

  final CustomerOrder order;
  final String locale;
  final String storeZone;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.orderTimelineSection,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          for (final c in order.comments.reversed)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(top: 6, end: 10),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: context.isDarkMode
                          ? Colors.white
                          : AppColors.brandPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (c.message.isNotEmpty)
                          Text(
                            c.message,
                            style: t.body.copyWith(
                              color: context.scaffoldHeading,
                            ),
                          ),
                        if (c.timestamp.isNotEmpty)
                          Text(
                            orderFmtStep(c.timestamp, locale, storeZone),
                            style: t.caption.copyWith(
                              color: context.scaffoldMuted,
                            ),
                          ),
                      ],
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
