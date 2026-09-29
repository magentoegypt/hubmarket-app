import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp.dart';
import '../../cart/presentation/cart_controller.dart';
import '../../catalog/domain/money.dart';
import '../../store_credit/data/store_credit_repository.dart';
import '../../store_credit/domain/store_credit.dart';
import '../../store_credit/presentation/store_credit_providers.dart';
import '../domain/checkout.dart';
import 'checkout_controller.dart';

/// Store credit on the cart being checked out (`Cart.hm_store_credit`).
@immutable
class CheckoutCreditState {
  const CheckoutCreditState({
    this.cartId,
    this.credit,
    this.busy = false,
    this.error,
  });

  /// The cart [credit] was read from.
  final String? cartId;

  /// Null until read, and for a guest, a server without store credit, or a
  /// failed read — the row then stays out of the payment step.
  final CartStoreCredit? credit;

  /// Credit is being used or given back.
  final bool busy;

  /// The last refusal, with the store's own (localized) message.
  final Object? error;

  /// "Use my credit" belongs on the payment step.
  bool get offered => credit?.offered ?? false;

  /// The credit on the order now, for the totals; null when none.
  Money? get applied =>
      credit != null && credit!.isApplied ? credit!.applied : null;
}

/// The payment step's "Use my credit" (Figma 18): reads the cart's credit
/// each time the step opens — once the shipping method, part of what credit
/// can cover, is on the cart — and uses or gives back as much as the order
/// allows. Checkout then re-reads the totals and the payment methods.
class CheckoutCreditController extends Notifier<CheckoutCreditState> {
  @override
  CheckoutCreditState build() {
    ref.listen<CheckoutStep>(checkoutControllerProvider.select((s) => s.step), (
      previous,
      next,
    ) {
      if (next == CheckoutStep.payment && previous != next) {
        unawaited(Future.microtask(load));
      }
    }, fireImmediately: true);
    // Credit belongs to one cart and one customer: a new cart (an order
    // placed, a guest cart merged at sign-in) or a sign-out forgets it.
    ref.listen<String>(cartControllerProvider.select((s) => s.cart.id), (
      previous,
      next,
    ) {
      if (state.cartId != null && state.cartId != next) {
        state = const CheckoutCreditState();
      }
    });
    // Signed out, or the store turned out to lack credit: forget it. Signed in
    // with credit available — the HubApp probe may settle after the step
    // opened — read it if the step is on screen.
    ref.listen<bool>(storeCreditEnabledProvider, (previous, next) {
      if (!next) {
        state = const CheckoutCreditState();
      } else if (previous == false &&
          ref.read(checkoutControllerProvider).step == CheckoutStep.payment) {
        unawaited(Future.microtask(load));
      }
    });
    return const CheckoutCreditState();
  }

  StoreCreditRepository get _repo => ref.read(storeCreditRepositoryProvider);

  String? get _cartId {
    final id = ref.read(cartControllerProvider).cart.id;
    return id.isEmpty ? null : id;
  }

  /// Reads the credit on the cart. Quiet: a failure leaves the row out and
  /// the order payable as before.
  Future<void> load() async {
    final cartId = _cartId;
    if (cartId == null || !ref.read(storeCreditEnabledProvider)) {
      state = const CheckoutCreditState();
      return;
    }
    try {
      final credit = await _repo.fetchCartCredit(cartId);
      if (_cartId != cartId || state.busy) return;
      state = CheckoutCreditState(cartId: cartId, credit: credit);
    } on HubAppMissing {
      markHubAppAccountMissing(ref);
      state = const CheckoutCreditState();
    } on Object {
      if (_cartId == cartId && !state.busy) {
        state = CheckoutCreditState(cartId: cartId);
      }
    }
  }

  /// Uses as much credit as the order allows ([use]) or gives it back, then
  /// has checkout re-read the totals (`hm_store_credit`, grand total) and the
  /// methods that can pay for them. False when the store refused — [state]
  /// then carries its message.
  Future<bool> setUse(bool use) async {
    final cartId = _cartId;
    final credit = state.credit;
    if (cartId == null || credit == null || state.busy) return false;
    if (use == credit.isApplied) return true;
    state = CheckoutCreditState(cartId: cartId, credit: credit, busy: true);
    try {
      final update = use
          ? await _repo.apply(cartId, usableAmount(credit))
          : await _repo.remove(cartId);
      state = CheckoutCreditState(
        cartId: cartId,
        credit: update.credit ?? credit,
      );
      await ref
          .read(checkoutControllerProvider.notifier)
          .refreshTotals(paymentMethods: update.paymentMethods);
      return true;
    } on HubAppMissing {
      markHubAppAccountMissing(ref);
      state = const CheckoutCreditState();
      return false;
    } on Object catch (error) {
      state = CheckoutCreditState(cartId: cartId, credit: credit, error: error);
      return false;
    }
  }

  /// `max_applicable` rounded down to whole fils: the server refuses more
  /// than the balance, which Vnecoms keeps to four decimals, while money
  /// answers are rounded to two — rounding up could ask for a fils too many.
  @visibleForTesting
  static double usableAmount(CartStoreCredit credit) =>
      ((credit.maxApplicable.amount * 100) + 1e-6).floorToDouble() / 100;
}

final checkoutCreditProvider =
    NotifierProvider<CheckoutCreditController, CheckoutCreditState>(
      CheckoutCreditController.new,
    );
