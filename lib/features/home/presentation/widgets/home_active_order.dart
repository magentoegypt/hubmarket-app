import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/config/store_timezone.dart';
import '../../../../core/util/store_time.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/domain/order.dart';
import '../active_order_providers.dart';
import '../../../../app/theme/hub_icons.dart';

/// The Home's active-order card, near the top of both Homes: shown to a
/// signed-in customer whose recent order is still open
/// ([activeOrderProvider]), and nothing at all otherwise — for a guest, while
/// it loads, without such an order, or when the lookup failed.
class HomeActiveOrder extends ConsumerWidget {
  const HomeActiveOrder({
    super.key,
    this.padding = const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
  });

  /// Around the card, only when there is one.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(activeOrderProvider).valueOrNull;
    if (order == null) return const SizedBox.shrink();
    return Padding(padding: padding, child: ActiveOrderCard(order: order));
  }
}

/// Figma 07 "Active order": a compact white card — green truck tile, the
/// order's status over its number, date and item count, and Track. Tapping
/// the card opens the order; Track opens its tracking.
///
/// Everything on it is the order's own data: core orders carry no delivery
/// estimate, so there is no "Arriving today" line.
class ActiveOrderCard extends ConsumerWidget {
  const ActiveOrderCard({super.key, required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    // Magento stamps order dates in the store's zone — see orderFmtDate.
    final storeZone = ref.watch(storeTimezoneProvider).valueOrNull ?? '';
    final status = order.status.trim();
    final details = [
      '#${order.number}',
      if (_shortDate(order.date, locale, storeZone) case final date?) date,
      if (order.itemCount > 0) l10n.orderItemCount(order.itemCount),
    ].join(' · ');
    final radius = BorderRadius.circular(12);
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: AppColors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(AppRoutes.orderDetail, extra: order),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.successSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  HubIcons.truck,
                  size: 20,
                  color: AppColors.successStrong,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.isEmpty ? l10n.orderNumber(order.number) : status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkHeading,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 16 / 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () =>
                    context.push(AppRoutes.orderTracking, extra: order),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(l10n.orderTrack),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "28 Sep" in [locale], read in the store's zone; null when [raw] can't
  /// be parsed.
  static String? _shortDate(String raw, String locale, String storeZone) {
    final placed = storeStampToLocal(raw, storeZone);
    if (placed == null) return null;
    try {
      return DateFormat('d MMM', locale).format(placed);
    } catch (_) {
      return DateFormat('d MMM').format(placed);
    }
  }
}
