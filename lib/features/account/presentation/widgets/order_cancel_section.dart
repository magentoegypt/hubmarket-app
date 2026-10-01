import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/config/store_features.dart';
import '../../../../core/widgets/button_spinner.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/order.dart';
import '../order_cancellation.dart';
import '../../../../core/widgets/hub_bottom_sheet.dart';
import '../../../../app/theme/hub_icons.dart';

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
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: context.scaffoldMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DangerButton(
            label: l10n.orderCancelAction,
            onPressed: () async {
              final outcome = await showCancelOrderSheet(
                context,
                order: order,
                reasons: features.cancellationReasons,
              );
              if (!context.mounted || outcome == null) return;
              final messenger = ScaffoldMessenger.of(context);
              switch (outcome) {
                case OrderCancelled(order: final updated):
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.orderCancelDone)),
                  );
                  if (updated != null) onCancelled(updated);
                case CancellationEmailSent():
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.orderCancelEmailSent)),
                  );
              }
            },
          ),
        ],
      ),
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
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.dangerSurface,
        foregroundColor: AppColors.danger,
        disabledBackgroundColor: AppColors.dangerSurface,
        disabledForegroundColor: AppColors.danger.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const ButtonSpinner()
          : Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
    ),
  );
}

/// Figma 21b: confirms the cancellation with one of the store's reasons and
/// performs it. Resolves to what happened, or null when the customer keeps
/// the order.
Future<CancelOutcome?> showCancelOrderSheet(
  BuildContext context, {
  required CustomerOrder order,
  required List<String> reasons,
}) => showHubBottomSheet<CancelOutcome>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  // White like the frame, not Material's tinted sheet surface.
  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => CancelOrderSheet(order: order, reasons: reasons),
);

class CancelOrderSheet extends ConsumerStatefulWidget {
  const CancelOrderSheet({
    super.key,
    required this.order,
    required this.reasons,
  });

  final CustomerOrder order;
  final List<String> reasons;

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final order = widget.order;
    final note = [
      l10n.orderCancelWholeOrder,
      if (order.hasInvoice) l10n.orderCancelRefundNote,
      if (order.placedAsGuest) l10n.orderCancelGuestNote,
    ].join(' ');
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.orderCancelTitle(order.number),
            style: TextStyle(
              fontFamily: AppTheme.displayFont,
              // Playfair has no Arabic glyphs.
              fontFamilyFallback: const [AppTheme.arabicFont],
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: context.scaffoldHeading,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  HubIcons.package,
                  size: 18,
                  color: AppColors.accentStrong,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    note,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.accentStrong,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.orderCancelReasonTitle,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.scaffoldHeading,
            ),
          ),
          const SizedBox(height: 6),
          for (final reason in widget.reasons) ...[
            _ReasonRow(
              label: reason,
              selected: reason == _reason,
              onTap: _busy ? null : () => setState(() => _reason = reason),
            ),
            Divider(height: 1, thickness: 1, color: context.hairline),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ],
          const SizedBox(height: 18),
          DangerButton(
            label: l10n.orderCancelAction,
            busy: _busy,
            onPressed: _confirm,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentStrong,
              minimumSize: const Size.fromHeight(48),
            ),
            child: Text(
              l10n.orderCancelKeep,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

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
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    inMutuallyExclusiveGroup: true,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 24,
              color: selected ? AppColors.brandPrimary : context.scaffoldMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14.5, color: context.scaffoldHeading),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
