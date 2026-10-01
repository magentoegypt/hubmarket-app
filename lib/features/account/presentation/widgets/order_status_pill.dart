import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../domain/order.dart';

/// Figma `--hm-returns`: the purple of "RETURN IN PROGRESS".
const Color kReturnsInk = Color(0xFF7C3AED);

/// Figma "status-pill": a 999 radius capsule — 8 px sides, 3 px top and bottom —
/// holding the status in EN/Micro (11 Bold) capitals. The tones are the frames':
/// blue out for delivery, amber processing, green delivered, red cancelled, grey
/// for a state without a tone of its own.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  /// Shown in capitals, as the frames write it.
  final String label;
  final Color background;
  final Color foreground;

  /// In flight: shipped or out for delivery.
  const StatusPill.info({super.key, required this.label})
    : background = AppColors.infoSubtle,
      foreground = AppColors.info;

  /// Waiting on the store: new, being prepared.
  const StatusPill.warning({super.key, required this.label})
    : background = AppColors.warningSubtle,
      foreground = AppColors.warning;

  /// Done: delivered, complete.
  const StatusPill.success({super.key, required this.label})
    : background = AppColors.successSubtle,
      foreground = AppColors.successStrong;

  /// Cancelled, closed, refused.
  const StatusPill.danger({super.key, required this.label})
    : background = AppColors.dangerSurface,
      foreground = AppColors.danger;

  /// No tone: on hold, or a status the app does not know.
  const StatusPill.neutral({super.key, required this.label})
    : background = AppColors.surfaceMuted,
      foreground = AppColors.inkMuted;

  /// A return the customer has open on the package (the frames' "RETURN IN
  /// PROGRESS", purple on the page grey).
  const StatusPill.returns({super.key, required this.label})
    : background = AppColors.surfaceSubtle,
      foreground = kReturnsInk;

  @override
  Widget build(BuildContext context) {
    final text = label.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.of(context).micro.copyWith(color: foreground),
      ),
    );
  }
}

/// The status of a whole order, in the store's own words: for the orders the
/// server did not split by store (no `hm_packages`), where one pill covers every
/// line. Tinted by what the backend recorded — delivered, cancelled, on hold,
/// shipped, else waiting.
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill({super.key, required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context) {
    final label = order.status;
    if (order.isCancelled) return StatusPill.danger(label: label);
    if (order.isDelivered) return StatusPill.success(label: label);
    if (order.isOnHold) return StatusPill.neutral(label: label);
    if (order.hasShipment || order.hasTracking) {
      return StatusPill.info(label: label);
    }
    return StatusPill.warning(label: label);
  }
}
