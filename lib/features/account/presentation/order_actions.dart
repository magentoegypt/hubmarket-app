import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/hub_icons.dart';
import '../../../app/theme/theme_x.dart';
import '../../../core/widgets/hub_bottom_sheet.dart';
import '../../../core/widgets/network_image.dart';
import '../../../l10n/l10n.dart';
import '../../cart/presentation/cart_controller.dart';
import '../domain/order.dart';

/// Re-adds every line of [order] to the cart (skipping items that can't be
/// re-added — out of stock / removed), shows a snackbar, and navigates to the
/// cart on success. Shared by the orders list card and the order detail page.
Future<void> reorderOrder(
  BuildContext context,
  WidgetRef ref,
  CustomerOrder order,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  final cart = ref.read(cartControllerProvider.notifier);
  var added = false;
  for (final line in order.lines) {
    final sku = line.sku;
    if (sku == null || sku.isEmpty) continue;
    try {
      await cart.addToCart(
        sku: sku,
        quantity: line.quantity.toInt().clamp(1, 99),
      );
      added = true;
    } catch (_) {
      // Skip items that can't be re-added (out of stock / removed).
    }
  }
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(added ? l10n.orderReorderAdded : l10n.orderReorderFailed),
    ),
  );
  if (added) context.push(AppRoutes.cart);
}

/// "Rate items" on a delivered order: the review form (Figma 15b) of the
/// order's product — or, when the order has several, of the one the customer
/// picks from a sheet. Lines the backend gave no SKU for can't be reviewed and
/// are not listed.
Future<void> rateOrderItems(BuildContext context, CustomerOrder order) async {
  final lines = [
    for (final line in order.lines)
      if ((line.sku ?? '').isNotEmpty) line,
  ];
  if (lines.isEmpty) return;
  final router = GoRouter.of(context);
  if (lines.length == 1) {
    router.push(AppRoutes.review(lines.single.sku!));
    return;
  }
  final picked = await showHubBottomSheet<OrderLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _RatePickSheet(lines: lines),
  );
  if (picked != null) router.push(AppRoutes.review(picked.sku!));
}

/// The sheet behind [rateOrderItems]: one row per product of the order.
class _RatePickSheet extends StatelessWidget {
  const _RatePickSheet({required this.lines});

  final List<OrderLine> lines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.orderRatePickTitle,
            style: t.heading2.copyWith(color: context.scaffoldHeading),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            InkWell(
              onTap: () => Navigator.of(context).pop(line),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: ColoredBox(
                          color: AppColors.surfaceSubtle,
                          child: HubImage(
                            url: line.imageUrl,
                            width: 48,
                            height: 48,
                            placeholder: (_) => const SizedBox.shrink(),
                            error: (_) => const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        line.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyStrong.copyWith(
                          color: context.scaffoldHeading,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      HubIcons.chevronRight,
                      size: 20,
                      color: context.scaffoldMuted,
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
