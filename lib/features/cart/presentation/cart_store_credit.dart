import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../catalog/domain/money.dart';
import '../../store_credit/data/store_credit_repository.dart';
import '../../store_credit/presentation/store_credit_providers.dart';
import 'cart_controller.dart';

/// The store credit used on the cart (`Cart.hm_store_credit.applied`), for
/// the cart's "Store credit" total line: credit applied at checkout is
/// already taken off the cart's grand total, so the cart says so.
///
/// Null — no line — in Build 1, for a guest, when no credit is applied, and
/// when the read fails. Read with the store-credit repository's own cart
/// query, again whenever the cart or its total changes.
final cartStoreCreditProvider = FutureProvider.autoDispose<Money?>((ref) async {
  if (!ref.watch(storeCreditEnabledProvider)) return null;
  final cart = ref.watch(
    cartControllerProvider.select(
      (s) => (id: s.cart.id, total: s.cart.totals.grandTotal),
    ),
  );
  if (cart.id.isEmpty) return null;
  try {
    final credit = await ref
        .watch(storeCreditRepositoryProvider)
        .fetchCartCredit(cart.id);
    return credit != null && credit.isApplied ? credit.applied : null;
  } on HubAppMissing {
    markHubAppAccountMissing(ref);
    return null;
  } on Failure {
    return null;
  }
});
