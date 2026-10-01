import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/store_features.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/order.dart';
import '../order_cancellation.dart';

/// The foot of an order screen (Figma 22): a note and "Cancel order", shown
/// only when [offersOrderCancel] allows it. Opens the 21b sheet; a customer's
/// cancelled order comes back through [onCancelled].
class OrderCancelSection extends ConsumerWidget {
  const OrderCancelSection({
    super.key,
    required this.order,
    required this.onCancelled,
  });

  final CustomerOrder order;
  final ValueChanged<CustomerOrder> onCancelled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Most orders don't offer CANCEL; don't read storeConfig for them.
    if (!order.offersCancel) return const SizedBox.shrink();
    final features =
        ref.watch(storeFeaturesProvider).valueOrNull ?? StoreFeatures.none;
    if (!offersOrderCancel(features, order)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDarkMode ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(HubIcons.info, size: 18, color: context.scaffoldMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.orderCancelHint,
                  style: t.caption.copyWith(color: context.scaffoldMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DangerButton(
            label: l10n.orderCancelAction,
            onPressed: () => startOrderCancel(
              context,
              order: order,
              reasons: features.cancellationReasons,
              onCancelled: onCancelled,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Cancel order" pressed: opens the 21b sheet and, once the customer confirms,
/// says what happened — cancelled (the updated order goes to [onCancelled]) or,
/// for a guest, that the e-mail with the confirming link is on its way. Shared
/// by the order detail's cancel card and the orders list.
Future<void> startOrderCancel(
  BuildContext context, {
  required CustomerOrder order,
  required List<String> reasons,
  ValueChanged<CustomerOrder>? onCancelled,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final outcome = await showCancelOrderSheet(
    context,
    order: order,
    reasons: reasons,
  );
  if (!context.mounted || outcome == null) return;
  switch (outcome) {
    case OrderCancelled(order: final updated):
      messenger.showSnackBar(SnackBar(content: Text(l10n.orderCancelDone)));
      if (updated != null) onCancelled?.call(updated);
    case CancellationEmailSent():
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.orderCancelEmailSent)),
      );
  }
}

/// The light-red destructive button of Figma 21b / 22.
class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => HubButton(
    label: label,
    style: HubButtonStyle.danger,
    loading: busy,
    onPressed: onPressed,
  );
}

/// Figma 21b: confirms the cancellation with one of the store's reasons and
/// performs it. Resolves to what happened, or null when the customer keeps
/// the order.
Future<CancelOutcome?> showCancelOrderSheet(
  BuildContext context, {
  required CustomerOrder order,
  required List<String> reasons,
}) {
  // The sheet keeps 30 px under its buttons (the frame), or the system
  // gesture area when that is taller: showHubBottomSheet already adds the
  // inset, so only what is missing to 30 px is added here. Read from the view:
  // under a Scaffold with a tab bar, MediaQuery has already used it up.
  final view = View.of(context);
  final inset = view.padding.bottom / view.devicePixelRatio;
  final bottomExtra = (30 - inset).clamp(0.0, 30.0);
  return showHubBottomSheet<CancelOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The sheet draws its own 40 px handle.
    showDragHandle: false,
    // White like the frame, not Material's tinted sheet surface; the page
    // behind is dimmed with the brand navy at 55 %.
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    barrierColor: AppColors.brandPrimary.withValues(alpha: 0.55),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => CancelOrderSheet(
      order: order,
      reasons: reasons,
      bottomExtra: bottomExtra,
    ),
  );
}

class CancelOrderSheet extends ConsumerStatefulWidget {
  const CancelOrderSheet({
    super.key,
    required this.order,
    required this.reasons,
    this.bottomExtra = 30,
  });

  final CustomerOrder order;
  final List<String> reasons;

  /// Space under the buttons, on top of the system inset.
  final double bottomExtra;

  @override
  ConsumerState<CancelOrderSheet> createState() => _CancelOrderSheetState();
}

class _CancelOrderSheetState extends ConsumerState<CancelOrderSheet> {
  late String _reason = widget.reasons.first;
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final outcome = await cancelOrder(ref, widget.order, _reason);
      if (mounted) Navigator.of(context).pop(outcome);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = serverMessageOr(context, error, l10n.errorGeneric);
      });
    }
  }

  /// "The whole order is cancelled — both packages (MIA CO and loly store).",
  /// or every item when the order was not split by store, then what a paid or
  /// guest order adds.
  String _note(AppLocalizations l10n) {
    final stores = <String>[];
    for (final package in widget.order.packages) {
      final name = package.seller?.name.trim() ?? '';
      if (name.isNotEmpty) stores.add(name);
    }
    final whole = stores.length >= 2
        ? l10n.orderCancelWholePackages(
            stores.length,
            _joinNames(l10n, stores),
          )
        : l10n.orderCancelWholeOrder;
    return [
      whole,
      if (widget.order.hasInvoice) l10n.orderCancelRefundNote,
      if (widget.order.placedAsGuest) l10n.orderCancelGuestNote,
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final order = widget.order;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        widget.bottomExtra + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle: 40 x 4, `--hm-default`.
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.orderCancelTitle(order.number),
            style: t.heading1.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warningSubtle,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  HubIcons.package,
                  size: 18,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _note(l10n),
                    style: t.caption.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.orderCancelReasonTitle,
            style: t.title.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 12),
          for (final reason in widget.reasons)
            _ReasonRow(
              label: reason,
              selected: reason == _reason,
              onTap: _busy ? null : () => setState(() => _reason = reason),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: t.caption.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DangerButton(
                  label: l10n.orderCancelAction,
                  busy: _busy,
                  onPressed: _confirm,
                ),
                const SizedBox(height: 10),
                HubButton(
                  label: l10n.orderCancelKeep,
                  style: HubButtonStyle.ghost,
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Anna, Ben and Cleo" in the app's language.
String _joinNames(AppLocalizations l10n, List<String> names) {
  if (names.length < 2) return names.join();
  final head = names.sublist(0, names.length - 1).join(l10n.listSeparator);
  return '$head${l10n.listAnd}${names.last}';
}

/// One reason: a 22 px radio (a navy ring round a white dot once chosen, a
/// 1.5 px `--hm-strong` ring before), the reason in EN/Body, a hairline under.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: context.isDarkMode
                    ? Colors.white12
                    : AppColors.borderSubtle,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.brandPrimary
                        : AppColors.borderControl,
                    width: selected ? 7 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: t.body.copyWith(color: context.scaffoldHeading),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
