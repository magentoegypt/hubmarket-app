import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/network/connectivity.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/account_repository.dart';
import '../../data/guest_order_store.dart';
import '../../domain/order.dart';
import 'order_detail_screen.dart';

/// The order [number] as this session may read it: the signed-in customer's
/// own (`customer.orders` filtered by number), or a guest order this device
/// remembers (placed or looked up here) through its token, else the e-mail
/// and last name it was placed with. Null when there is no such order.
final orderByNumberProvider = FutureProvider.autoDispose
    .family<CustomerOrder?, String>((ref, number) async {
      // Labels, prices and currency are per store view.
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      final signedIn = ref.watch(
        authControllerProvider.select((a) => a.isAuthenticated),
      );
      final repository = ref.watch(accountRepositoryProvider);
      if (signedIn) return repository.fetchOrderByNumber(number);
      final remembered = ref
          .read(guestOrderStoreProvider)
          .where((entry) => entry.number == number && entry.isResolvable)
          .firstOrNull;
      if (remembered == null) return null;
      if (remembered.hasToken) {
        return repository.fetchGuestOrderByToken(remembered.token!);
      }
      return repository.fetchGuestOrder(
        number: number,
        email: remembered.email!,
        lastname: remembered.lastname!,
      );
    });

/// An order opened by its number rather than handed over by a list: a push,
/// a link (`/orders/<number>`, `/order-detail?number=`) or Order placed's
/// "Track order" (19).
///
/// A signed-in customer gets the order's detail (Figma 22) once
/// `customer.orders` returns it, and "Order not found" when it doesn't. A
/// guest gets it when this device remembers the order; otherwise Track order
/// (26) takes over with the number filled in, since a guest order is only
/// readable with the e-mail and last name it was placed with.
class OrderLinkScreen extends ConsumerStatefulWidget {
  const OrderLinkScreen({super.key, required this.number});

  /// The increment id customers see, e.g. `000000248`.
  final String number;

  @override
  ConsumerState<OrderLinkScreen> createState() => _OrderLinkScreenState();
}

class _OrderLinkScreenState extends ConsumerState<OrderLinkScreen> {
  bool _sentToTrackOrder = false;

  void _sendToTrackOrder() {
    if (_sentToTrackOrder) return;
    _sentToTrackOrder = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GoRouter.of(
        context,
      ).pushReplacement(AppRoutes.guestTrackOrderFor(widget.number));
    });
  }

  void _retry() => ref.invalidate(orderByNumberProvider(widget.number));

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authControllerProvider.select((a) => a.status));
    final remembered = ref.watch(
      guestOrderStoreProvider.select(
        (refs) => refs.any((entry) => entry.number == widget.number),
      ),
    );
    // The session is still being restored: a cold start from a push.
    if (status == AuthStatus.unknown) return const _Frame(child: _Loading());
    if (status == AuthStatus.guest && !remembered) {
      _sendToTrackOrder();
      return const _Frame(child: _Loading());
    }
    return ref
        .watch(orderByNumberProvider(widget.number))
        .when(
          // Retry shows the spinner rather than the last error.
          skipLoadingOnRefresh: false,
          loading: () => const _Frame(child: _Loading()),
          error: (error, _) => _Frame(
            child: _LoadError(error: error, onRetry: _retry),
          ),
          data: (order) => order == null
              ? _Frame(child: _NotFound(number: widget.number))
              : OrderDetailScreen(order: order),
        );
  }
}

/// The order detail's app bar over [child], so nothing jumps when the order
/// arrives.
class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AppLocalizations.of(context).orderDetailsTitle)),
    body: child,
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _NotFound extends StatelessWidget {
  const _NotFound({required this.number});

  final String number;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return EmptyState(
      icon: Icons.receipt_long_outlined,
      title: l10n.orderNotFoundTitle,
      body: l10n.orderNotFoundBody(number),
      action: OutlinedButton(
        onPressed: () => context.go(AppRoutes.orders),
        child: Text(l10n.accountOrders),
      ),
    );
  }
}

/// Offline, or the store's own trouble, with Retry.
class _LoadError extends ConsumerWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isNetworkFailure(error) || ref.watch(isOfflineProvider)) {
      return OfflineState(onRetry: onRetry);
    }
    final l10n = AppLocalizations.of(context);
    final failure = error;
    return EmptyState(
      icon: Icons.cloud_off_outlined,
      title: failure is Failure
          ? failureMessage(context, failure)
          : l10n.errorGeneric,
      action: FilledButton(onPressed: onRetry, child: Text(l10n.actionRetry)),
    );
  }
}
