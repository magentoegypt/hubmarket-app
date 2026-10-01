import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/util/launch.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../domain/order.dart';
import '../../../../app/theme/hub_icons.dart';

/// One store's part of an order as the order screens show it: its lines and
/// store and — when the server split the order (`hm_packages`, HubAppOrders) —
/// the [package] itself, with its status, shipments and totals.
@immutable
class OrderPackageView {
  const OrderPackageView({required this.lines, this.seller, this.package});

  /// Null for lines the backend named no seller for.
  final HmSellerSummary? seller;
  final List<OrderLine> lines;
  final OrderPackage? package;
}

/// The order's lines by package, or null for today's single list:
///
/// * the server's packages (`hm_packages`) in its order, each with the lines
///   its `item_uids` name — a line no package names (none should) closes the
///   list in a group of its own;
/// * else each line's seller (`hm_seller`, HubAppVendors), stores in the order
///   they first appear;
/// * else null: the server has neither.
List<OrderPackageView>? orderPackageViews(CustomerOrder order) {
  if (order.packages.isNotEmpty) {
    final byUid = <String, OrderLine>{
      for (final line in order.lines)
        if (line.uid case final uid?) uid: line,
    };
    final placed = <String>{};
    final views = <OrderPackageView>[];
    for (final package in order.packages) {
      final lines = <OrderLine>[];
      for (final uid in package.itemUids) {
        final line = byUid[uid];
        if (line != null && placed.add(uid)) lines.add(line);
      }
      if (lines.isNotEmpty) {
        views.add(
          OrderPackageView(
            seller: package.seller,
            lines: List.unmodifiable(lines),
            package: package,
          ),
        );
      }
    }
    // Packages that name none of the order's lines are no split to show.
    if (views.isNotEmpty) {
      final rest = [
        for (final line in order.lines)
          if (!placed.contains(line.uid)) line,
      ];
      if (rest.isNotEmpty) {
        views.add(OrderPackageView(lines: List.unmodifiable(rest)));
      }
      return List.unmodifiable(views);
    }
  }
  final groups = groupBySeller<OrderLine>(order.lines, (l) => l.seller);
  if (groups == null) return null;
  return List.unmodifiable([
    for (final group in groups)
      OrderPackageView(seller: group.seller, lines: group.items),
  ]);
}

/// The tracking numbers the package cards of [views] already show.
Set<String> packagedTrackingNumbers(List<OrderPackageView>? views) => {
  for (final view in views ?? const <OrderPackageView>[])
    if (view.package case final package?)
      for (final track in package.tracks) track.number,
};

/// Whether a package card of [views] shows a shipment.
bool anyPackageShipped(List<OrderPackageView>? views) =>
    views?.any((view) => view.package?.hasShipments ?? false) ?? false;

/// Figma 22 "Package N · store": one store's items of an order. With the
/// server's packages (HubAppOrders) the card also carries the package's own
/// status, its shipments — "Track parcel" where the carrier has a public page,
/// the carrier and the number to copy otherwise — what the store told the
/// customer, and the package's totals. The frame's delivery estimate has no
/// source and stays out.
class OrderPackageCard extends StatelessWidget {
  const OrderPackageCard({
    super.key,
    required this.index,
    required this.view,
    required this.line,
  });

  /// 1-based, in the order the packages come.
  final int index;
  final OrderPackageView view;
  final Widget Function(OrderLine line) line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seller = view.seller;
    final package = view.package;
    final title = seller != null
        ? l10n.orderPackageTitle(index, seller.name)
        : l10n.orderPackageTitleNoStore(index);
    Widget divider() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Divider(height: 1, color: context.hairline),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 8),
      decoration: BoxDecoration(
        border: Border.all(color: context.hairline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: seller != null
                    ? SellerGroupHeader(seller: seller, title: title)
                    : Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.scaffoldHeading,
                        ),
                      ),
              ),
              if (package != null) ...[
                const SizedBox(width: 8),
                OrderPackageStatusPill(package: package),
              ],
            ],
          ),
          if (package?.shippingMethod case final method?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                method,
                style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
              ),
            ),
          divider(),
          for (final item in view.lines) line(item),
          if (package != null && package.hasShipments) ...[
            divider(),
            for (final shipment in package.shipments)
              _ShipmentBlock(shipment: shipment),
          ],
          if (package != null && package.comments.isNotEmpty) ...[
            divider(),
            _StoreUpdates(comments: package.comments),
          ],
          if (package?.grandTotal case final total?) ...[
            divider(),
            _PackageTotals(package: package!, total: total),
          ],
        ],
      ),
    );
  }
}

/// The package's own status, in the store's words: amber while it is being
/// prepared, blue once part of it shipped, green when complete, red when
/// cancelled or closed, grey on hold (Figma 22 "OUT FOR DELIVERY" /
/// "PROCESSING").
class OrderPackageStatusPill extends StatelessWidget {
  const OrderPackageStatusPill({super.key, required this.package});

  final OrderPackage package;

  @override
  Widget build(BuildContext context) {
    final label = package.statusLabel.trim();
    if (label.isEmpty) return const SizedBox.shrink();
    final (background, foreground) = switch (package.stage) {
      OrderPackageStage.complete => (
        AppColors.successSubtle,
        AppColors.successStrong,
      ),
      OrderPackageStage.canceled => (AppColors.dangerSurface, AppColors.danger),
      OrderPackageStage.onHold ||
      OrderPackageStage.unknown => (AppColors.surfaceMuted, AppColors.inkMuted),
      OrderPackageStage.processing when package.hasShipments => (
        AppColors.infoSubtle,
        AppColors.info,
      ),
      OrderPackageStage.pending || OrderPackageStage.processing => (
        AppColors.warningSubtle,
        AppColors.warning,
      ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            height: 14 / 11,
            fontWeight: FontWeight.w700,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

/// "Shipment #000000031 · 29 Sep" and its tracking numbers.
class _ShipmentBlock extends StatelessWidget {
  const _ShipmentBlock({required this.shipment});

  final OrderPackageShipment shipment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final date = _formatInstant(shipment.createdAt, locale);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                HubIcons.truck,
                size: 18,
                color: _accent(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.orderPackageShipment(shipment.number),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.scaffoldHeading,
                  ),
                ),
              ),
              if (date.isNotEmpty)
                Text(
                  date,
                  style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
                ),
            ],
          ),
          for (final track in shipment.tracks) PackageTrackRow(track: track),
        ],
      ),
    );
  }
}

/// A tracking number: the carrier and the number (kept left-to-right, an
/// Arabic layout must not reverse it) with a copy action, and "Track parcel"
/// when the carrier's page can be opened.
class PackageTrackRow extends ConsumerWidget {
  const PackageTrackRow({super.key, required this.track});

  final OrderPackageTrack track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final url = track.trackingUrl;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 26, top: 4),
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
                      track.carrierTitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.scaffoldMuted,
                      ),
                    ),
                    Text(
                      track.number,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
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
                  await Clipboard.setData(ClipboardData(text: track.number));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.orderTrackingCopied)),
                    );
                  }
                },
              ),
            ],
          ),
          if (url != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: FilledButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final opened = await ref.read(externalUriLauncherProvider)(
                    url,
                  );
                  if (!opened) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.errorGeneric)),
                    );
                  }
                },
                icon: const Icon(HubIcons.truck, size: 18),
                label: Text(l10n.orderTrackParcel),
              ),
            ),
        ],
      ),
    );
  }
}

/// What the store told the customer about the package, newest first.
class _StoreUpdates extends StatelessWidget {
  const _StoreUpdates({required this.comments});

  final List<OrderPackageComment> comments;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.orderPackageUpdates,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.scaffoldHeading,
          ),
        ),
        for (final comment in comments.reversed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsetsDirectional.only(top: 5, end: 10),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _accent(context),
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.message,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.scaffoldHeading,
                        ),
                      ),
                      if (_formatInstant(comment.createdAt, locale)
                          case final time when time.isNotEmpty)
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 12,
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
    );
  }
}

/// The package's subtotal, discount, its own delivery (only when the order paid
/// delivery per store), tax and total.
class _PackageTotals extends StatelessWidget {
  const _PackageTotals({required this.package, required this.total});

  final OrderPackage package;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        if (package.subtotal case final subtotal?)
          _TotalLine(label: l10n.cartSubtotal, amount: subtotal),
        if (package.discount case final discount?)
          _TotalLine(
            label: l10n.cartDiscount,
            amount: discount,
            negative: true,
          ),
        if (package.shippingAmount case final shipping?)
          _TotalLine(label: l10n.orderShippingLabel, amount: shipping),
        if (package.tax case final tax?)
          _TotalLine(label: l10n.orderPackageTax, amount: tax),
        _TotalLine(label: l10n.orderPackageTotal, amount: total, strong: true),
      ],
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine({
    required this.label,
    required this.amount,
    this.negative = false,
    this.strong = false,
  });

  final String label;
  final Money amount;
  final bool negative;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 13,
      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
      color: strong ? context.scaffoldHeading : context.scaffoldMuted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            negative ? '−${amount.formatted()}' : amount.formatted(),
            textDirection: TextDirection.ltr,
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Navy marks on the card; white on the dark scaffold, where navy vanishes.
Color _accent(BuildContext context) =>
    context.isDarkMode ? Colors.white : AppColors.brandPrimary;

/// A UTC instant as a short local date and time (`29 Sep, 9:10 AM`) in the
/// app's language; empty without one.
String _formatInstant(DateTime? at, String locale) {
  if (at == null) return '';
  final local = at.toLocal();
  try {
    return DateFormat('d MMM, h:mm a', locale).format(local);
  } catch (_) {
    return DateFormat('d MMM, h:mm a').format(local);
  }
}
