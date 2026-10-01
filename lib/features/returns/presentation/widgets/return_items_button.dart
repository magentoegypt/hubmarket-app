import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/domain/order.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../returns_providers.dart';
import '../../../../app/theme/hub_icons.dart';

/// Return items on the order detail (Figma 22): shown when returns are on,
/// the order is the signed-in customer's, and the server says it has
/// something left to return (`hmReturnableOrder`: processing or complete,
/// one request). Opens the return form (23) on this order.
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
        .watch(returnableOrderProvider(order.number))
        .valueOrNull;
    if (returnable == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: HubButton(
        label: l10n.returnsReturnItems,
        icon: HubIcons.rotateCcw,
        iconSize: 20,
        style: HubButtonStyle.outline,
        onPressed: () => context.push(
          AppRoutes.returnRequestFor(order.number),
          extra: returnable,
        ),
      ),
    );
  }
}
