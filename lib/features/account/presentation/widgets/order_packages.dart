import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/grouped_list.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../../stores/presentation/stores_providers.dart';
import '../../domain/order.dart';
import '../order_format.dart';
import 'order_status_pill.dart';

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

/// The Unicode isolates that keep a number left to right inside Arabic text.
final String _lri = String.fromCharCode(0x2066);
final String _pdi = String.fromCharCode(0x2069);

/// The seller's `tel:` link — what "Contact store" dials — read from its store
/// page, which carries the number only with the P3.1 seller fields
/// (HubAppVendors) and only while the admin shows seller phones. Null
/// otherwise: the button stays out.
final orderContactPhoneProvider = Provider.autoDispose.family<Uri?, String>((
  ref,
  storeCode,
) {
  if (!ref.watch(storeExtrasProvider)) return null;
  return ref.watch(storeProfileProvider(storeCode)).valueOrNull?.phoneUri;
});

enum _StepState { done, current, pending, danger }

/// One line of a shipment under "Shipped": its day and, when there is one, a
/// tracking number to copy.
@immutable
class _ShipLine {
  const _ShipLine({
    this.day = '',
    this.carrier = '',
    this.number = '',
    this.copyable = false,
  });

  final String day;
  final String carrier;
  final String number;

  /// A copy action follows the number: the carrier page "Track parcel"
  /// opens is the one place the frame lets it go without one.
  final bool copyable;

  String get text => [
    if (day.isNotEmpty) day,
    if (number.isNotEmpty)
      [if (carrier.isNotEmpty) carrier, '$_lri$number$_pdi'].join(' '),
  ].join(' · ');
}

@immutable
class _Step {
  const _Step(this.label, this.state, {this.sub = '', this.ships = const []});

  final String label;
  final _StepState state;

  /// A line under the label (the day), in muted ink.
  final String sub;

  /// The shipment lines under "Shipped".
  final List<_ShipLine> ships;
}

/// Figma 22 "package N": one store's part of an order — its logo, name and own
/// status, the timeline of where it stands, its items with their totals, and
/// what the customer can do with it: Track parcel (a carrier page the server
/// has a link for) and Contact store (the seller's phone, where the store
/// page has one).
///
/// The timeline follows what the backend recorded: the order confirmed, the
/// store preparing it, a shipment (with its day and tracking number), and
/// delivery when the package is complete. The frame's "Out for delivery" and
/// delivery estimate have no source and stay out; a package with no server
/// split (`package == null`) shows its lines only.
class OrderPackageCard extends ConsumerWidget {
  const OrderPackageCard({
    super.key,
    required this.index,
    required this.view,
    required this.order,
    this.line,
    this.title,
    this.statusPill,
  });

  /// 1-based, in the order the packages come.
  final int index;
  final OrderPackageView view;

  /// The order the package belongs to (its day is the first step's).
  final CustomerOrder order;

  /// A line's row; [OrderLineRow] when null.
  final Widget Function(OrderLine line)? line;

  /// Replaces "Package 1 · loly store" — the heading of the lines of an
  /// order the server did not split by store.
  final String? title;

  /// Replaces the package's status pill (the order's own, without packages).
  final Widget? statusPill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final zone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    final seller = view.seller;
    final package = view.package;
    final heading =
        title ??
        (seller != null
            ? l10n.orderPackageTitle(index, seller.name)
            : l10n.orderPackageTitleNoStore(index));
    final method = package?.shippingMethod?.trim() ?? '';
    final caption = [
      l10n.orderItemCount(view.lines.length),
      if (method.isNotEmpty) method,
    ].join(' · ');
    final parcelTrack = package?.tracks
        .where((track) => track.trackingUrl != null)
        .firstOrNull;
    final steps = package == null
        ? null
        : _steps(l10n, order, package, locale, zone, parcelTrack);
    final parcel = parcelTrack;
    final storeCode = seller?.storeCode;
    final phone = storeCode == null
        ? null
        : ref.watch(orderContactPhoneProvider(storeCode));
    // Two buttons share the row; the frame lets their content run into the
    // 24 px padding, so it is 8 here and neither label is cut.
    final sideBySide = parcel != null && phone != null;
    final actions = <Widget>[
      if (parcel != null)
        HubButton(
          label: l10n.orderTrackParcel,
          icon: HubIcons.truck,
          iconSize: 20,
          horizontalPadding: sideBySide ? 8 : 24,
          onPressed: () => _open(context, ref, parcel.trackingUrl!),
        ),
      if (phone != null)
        HubButton(
          label: l10n.orderContactStore,
          icon: HubIcons.phone,
          iconSize: 20,
          horizontalPadding: sideBySide ? 8 : 24,
          style: HubButtonStyle.outline,
          onPressed: () => _open(context, ref, phone),
        ),
    ];
    final children = <Widget>[
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
                  heading,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.title.copyWith(color: context.scaffoldHeading),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: context.scaffoldMuted),
                ),
              ],
            ),
          ),
          if (statusPill != null || package != null) ...[
            const SizedBox(width: 8),
            statusPill ?? OrderPackageStatusPill(package: package!),
          ],
        ],
      ),
      if (steps != null) _Timeline(steps: steps),
      Divider(
        height: 1,
        thickness: 1,
        color: context.isDarkMode ? Colors.white12 : AppColors.borderSubtle,
      ),
      for (final item in view.lines) (line ?? OrderLineRow.new)(item),
      if (package != null && package.comments.isNotEmpty)
        _StoreUpdates(comments: package.comments),
      if (actions.isNotEmpty)
        Row(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: actions[i]),
            ],
          ],
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: groupCardColor(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = AppLocalizations.of(context).errorGeneric;
    final opened = await ref.read(externalUriLauncherProvider)(uri);
    if (!opened) messenger.showSnackBar(SnackBar(content: Text(failed)));
  }

  /// Where the package stands, from what the backend recorded.
  List<_Step> _steps(
    AppLocalizations l10n,
    CustomerOrder order,
    OrderPackage package,
    String locale,
    String zone,
    OrderPackageTrack? parcel,
  ) {
    final confirmed = _Step(
      l10n.orderStepConfirmed,
      _StepState.done,
      sub: orderFmtStep(order.date, locale, zone),
    );
    switch (package.stage) {
      case OrderPackageStage.canceled:
        return [confirmed, _Step(l10n.orderStatusCancelled, _StepState.danger)];
      case OrderPackageStage.onHold:
        return [confirmed, _Step(l10n.orderStatusOnHold, _StepState.current)];
      case OrderPackageStage.pending:
      case OrderPackageStage.processing:
      case OrderPackageStage.complete:
      case OrderPackageStage.unknown:
        break;
    }
    final complete = package.stage == OrderPackageStage.complete;
    final past = package.hasShipments || complete;
    return [
      confirmed,
      _Step(
        past ? l10n.orderStepPrepared : l10n.orderStepPreparing,
        past ? _StepState.done : _StepState.current,
      ),
      _Step(
        l10n.orderStepShipped,
        past ? _StepState.done : _StepState.pending,
        ships: [
          for (final shipment in package.shipments)
            ..._shipLines(shipment, locale, parcel),
        ],
      ),
      _Step(
        l10n.orderStepDelivered,
        complete
            ? _StepState.done
            : (past ? _StepState.current : _StepState.pending),
      ),
    ];
  }

  List<_ShipLine> _shipLines(
    OrderPackageShipment shipment,
    String locale,
    OrderPackageTrack? parcel,
  ) {
    final at = shipment.createdAt;
    final day = at == null ? '' : orderFmtStepAt(at, locale);
    if (shipment.tracks.isEmpty) return [_ShipLine(day: day)];
    return [
      for (final track in shipment.tracks)
        _ShipLine(
          day: day,
          carrier: track.carrierTitle,
          number: track.number,
          copyable: !identical(track, parcel),
        ),
    ];
  }
}

/// Figma 22 "timeline": one row per step — a 20 px circle on a rail (green with
/// a tick when done, blue with a dot for the step the package is at, an empty
/// ring ahead, red for a cancelled one), its label and the line under it.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.steps});

  final List<_Step> steps;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < steps.length; i++)
        _StepRow(step: steps[i], last: i == steps.length - 1),
    ],
  );
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.last});

  final _Step step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final done = step.state == _StepState.done;
    final current = step.state == _StepState.current;
    final pending = step.state == _StepState.pending;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          child: Column(
            children: [
              _Dot(state: step.state),
              if (!last)
                Container(
                  width: 2,
                  height: 22,
                  color: done ? AppColors.successStrong : AppColors.borderStrong,
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
                step.label,
                style: (current ? t.bodyStrong : t.body).copyWith(
                  color: pending
                      ? context.scaffoldMuted
                      : step.state == _StepState.danger
                      ? AppColors.danger
                      : context.scaffoldHeading,
                ),
              ),
              if (step.sub.isNotEmpty)
                Text(
                  step.sub,
                  style: t.caption.copyWith(
                    color: current ? AppColors.info : context.scaffoldMuted,
                  ),
                ),
              for (final ship in step.ships) _ShipLineView(ship: ship),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final _StepState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _StepState.done:
        return _disc(
          AppColors.successStrong,
          const Icon(HubIcons.check, size: 12, color: Colors.white),
        );
      case _StepState.danger:
        return _disc(
          AppColors.danger,
          const Icon(HubIcons.x, size: 12, color: Colors.white),
        );
      case _StepState.current:
        return _disc(
          AppColors.info,
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        );
      case _StepState.pending:
        return Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderStrong, width: 2),
          ),
        );
    }
  }

  Widget _disc(Color color, Widget child) => Container(
    width: 20,
    height: 20,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );
}

/// "29 Sep, 09:10 · Aramex 3345 1182" under Shipped, with a copy action when
/// there is a number to copy.
class _ShipLineView extends StatelessWidget {
  const _ShipLineView({required this.ship});

  final _ShipLine ship;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    if (ship.text.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Flexible(
          child: Text(
            ship.text,
            style: t.caption.copyWith(color: context.scaffoldMuted),
          ),
        ),
        if (ship.number.isNotEmpty && ship.copyable)
          Semantics(
            button: true,
            label: l10n.orderCopyTrackingNumber,
            excludeSemantics: true,
            child: Tooltip(
              message: l10n.orderCopyTrackingNumber,
              child: InkResponse(
                radius: 16,
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final copied = l10n.orderTrackingCopied;
                  await Clipboard.setData(ClipboardData(text: ship.number));
                  messenger.showSnackBar(SnackBar(content: Text(copied)));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    HubIcons.copy,
                    size: 14,
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

/// The package's status in the store's own words, as a pill: blue once part of
/// it shipped, amber while it is being prepared, green when complete, red when
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
      child: StatusPill(
        label: label,
        background: background,
        foreground: foreground,
      ),
    );
  }
}

/// An order line as Figma 22 draws it: a 56 px thumbnail (radius 10 on the page
/// grey), the name on one line, "Qty 2" and the line's total.
class OrderLineRow extends StatelessWidget {
  const OrderLineRow(this.line, {super.key});

  final OrderLine line;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final unit = line.price;
    final total = unit == null
        ? null
        : Money(amount: unit.amount * line.quantity, currency: unit.currency);
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 56,
            height: 56,
            child: ColoredBox(
              color: context.isDarkMode
                  ? Colors.white10
                  : AppColors.surfaceSubtle,
              child: HubImage(
                url: line.imageUrl,
                width: 56,
                height: 56,
                placeholder: (_) => const SizedBox.shrink(),
                error: (_) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
              ),
              const SizedBox(height: 2),
              Text(
                // "Colour: Teal · Qty 1" — the options the customer chose.
                [...line.options, l10n.orderQty(line.quantity.toInt())].join(
                  ' · ',
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(color: context.scaffoldMuted),
              ),
            ],
          ),
        ),
        if (total != null) ...[
          const SizedBox(width: 12),
          Text(
            total.formatted(),
            textDirection: TextDirection.ltr,
            style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
          ),
        ],
      ],
    );
  }
}

/// What the store told the customer about the package (the website's "About
/// Your Order"), newest first.
class _StoreUpdates extends StatelessWidget {
  const _StoreUpdates({required this.comments});

  final List<OrderPackageComment> comments;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.orderPackageUpdates,
          style: t.captionStrong.copyWith(color: context.scaffoldHeading),
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
                      Text(
                        comment.message,
                        style: t.body.copyWith(color: context.scaffoldHeading),
                      ),
                      if (comment.createdAt case final at?)
                        Text(
                          orderFmtStepAt(at, locale),
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
    );
  }
}
