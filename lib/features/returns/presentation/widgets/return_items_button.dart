import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/domain/order.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../returns_providers.dart';

/// Return items on the order detail (Figma 22): shown when returns are on,
/// the order is the signed-in customer's, and the server lists it among the
/// customer's returnable orders (processing or complete, with something left
/// to return). Opens the return form (23) on this order.
///
/// Nothing is shown while that is being checked, or when it can't be.
class ReturnItemsButton extends ConsumerWidget {
  const ReturnItemsButton({super.key, required this.order});

  final CustomerOrder order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order.placedAsGuest || order.number.isEmpty) {
      return const SizedBox.shrink();
    }
    if (!ref.watch(returnsAvailableProvider)) return const SizedBox.shrink();
    if (!ref.watch(authControllerProvider.select((s) => s.isAuthenticated))) {
      return const SizedBox.shrink();
    }
    final returnable = ref
        .watch(
          returnableOrderProvider((number: order.number, placedAt: order.date)),
        )
        .valueOrNull;
    if (returnable == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: OutlinedButton.icon(
          onPressed: () => context.push(
            AppRoutes.returnRequestFor(order.number),
            extra: returnable,
          ),
          icon: const Icon(Icons.replay, size: 20),
          label: Text(
            l10n.returnsReturnItems,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandPrimary,
            side: const BorderSide(color: AppColors.brandPrimary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }
}
