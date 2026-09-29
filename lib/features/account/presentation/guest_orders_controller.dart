import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/store/store_controller.dart';
import '../data/account_repository.dart';
import '../data/guest_order_store.dart';
import '../domain/order.dart';

/// Guest "My Orders": the orders this device remembers, re-fetched live.
///
/// [unresolved] holds refs whose lookup failed this load. They are deliberately
/// **kept**, not dropped — a network blip must not delete the only record a
/// guest has of their order. The screen offers Retry / Remove instead.
class GuestOrdersState {
  const GuestOrdersState({
    this.orders = const <CustomerOrder>[],
    this.unresolved = const <GuestOrderRef>[],
    this.isLoading = true,
    this.error,
  });

  final List<CustomerOrder> orders;
  final List<GuestOrderRef> unresolved;
  final bool isLoading;

  /// Set only when *nothing* could be resolved, so the screen can show a single
  /// retryable error instead of a list of broken rows.
  final Object? error;

  bool get isEmpty => orders.isEmpty && unresolved.isEmpty;
}

/// Resolves the persisted [GuestOrderRef]s into live [CustomerOrder]s via
/// Magento's native `guestOrderByToken` / `guestOrder` queries, and performs
/// manual lookups from the Track-Order form.
class GuestOrdersController extends AutoDisposeNotifier<GuestOrdersState> {
  @override
  GuestOrdersState build() {
    // Order content is store-scoped (labels, prices, currency), so re-resolve
    // when the language/store switches — same contract as `OrdersController`.
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next) Future.microtask(load);
      },
    );
    // Re-resolve whenever the remembered set changes (order placed, entry
    // removed, order looked up).
    ref.listen<List<GuestOrderRef>>(guestOrderStoreProvider, (prev, next) {
      if (prev != null && prev.length != next.length) Future.microtask(load);
    });
    Future.microtask(load);
    return const GuestOrdersState();
  }

  AccountRepository get _repo => ref.read(accountRepositoryProvider);

  Future<CustomerOrder> _resolve(GuestOrderRef entry) {
    // Prefer the token: it authorizes on its own and carries no personal data.
    if (entry.hasToken) return _repo.fetchGuestOrderByToken(entry.token!);
    return _repo.fetchGuestOrder(
      number: entry.number,
      email: entry.email!,
      lastname: entry.lastname!,
    );
  }

  Future<void> load() async {
    final refs = ref.read(guestOrderStoreProvider);
    if (refs.isEmpty) {
      state = const GuestOrdersState(isLoading: false);
      return;
    }
    state = GuestOrdersState(
      orders: state.orders,
      unresolved: state.unresolved,
      isLoading: true,
    );
    final orders = <CustomerOrder>[];
    final unresolved = <GuestOrderRef>[];
    Object? lastError;
    for (final r in refs) {
      try {
        orders.add(await _resolve(r));
      } on Object catch (error) {
        lastError = error;
        unresolved.add(r);
      }
    }
    state = GuestOrdersState(
      orders: orders,
      unresolved: unresolved,
      isLoading: false,
      // Only a total wipeout becomes a screen-level error.
      error: orders.isEmpty ? lastError : null,
    );
  }

  Future<void> refresh() => load();

  /// Stops tracking an order on this device. Local only — nothing is deleted
  /// server-side.
  Future<void> forget(String number) =>
      ref.read(guestOrderStoreProvider.notifier).forget(number);

  /// Manual lookup from the Track-Order form. Remembers the order on success so
  /// it shows up in the list from then on. Throws the mapped failure (Magento
  /// answers an unknown order with its own message) for the caller to surface.
  Future<CustomerOrder> lookup({
    required String number,
    required String email,
    required String lastname,
  }) async {
    final order = await _repo.fetchGuestOrder(
      number: number,
      email: email,
      lastname: lastname,
    );
    await ref
        .read(guestOrderStoreProvider.notifier)
        .remember(
          GuestOrderRef(
            number: order.number.isNotEmpty ? order.number : number,
            email: email,
            lastname: lastname,
            placedAt: order.date,
          ),
        );
    return order;
  }
}

final guestOrdersControllerProvider =
    AutoDisposeNotifierProvider<GuestOrdersController, GuestOrdersState>(
      GuestOrdersController.new,
    );
