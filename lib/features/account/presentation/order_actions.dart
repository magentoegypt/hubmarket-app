import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
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
