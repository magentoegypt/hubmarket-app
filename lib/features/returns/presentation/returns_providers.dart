import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/hubapp/hubapp.dart';
import '../../../core/store/store_controller.dart';
import '../../catalog/domain/money.dart';
import '../data/returns_repository.dart';
import '../domain/returns.dart';

/// Whether returns are offered at all: My returns on Account (20), Return
/// items on an order (22), the screens behind them and the Help FAQ's returns
/// answer.
///
/// On only when the HubApp probe found the module, its `returns` feature flag
/// is on (off unless the backend switches it on), and no returns request has
/// found the returns API missing this session. Otherwise — including while
/// the probe is still running or couldn't tell — the app behaves as Build 1,
/// which had no returns.
final returnsAvailableProvider = Provider<bool>((ref) {
  if (ref.watch(hubAppStatusProvider) != HubAppStatus.available) return false;
  if (!(ref.watch(hubAppFlagProvider('returns')) ?? false)) return false;
  return !ref.watch(returnsModuleMissingProvider);
});

/// The return form's settings (reasons in the Store header's language).
final returnConfigProvider = FutureProvider.autoDispose<ReturnConfig>((ref) {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  return ref.watch(returnsRepositoryProvider).fetchConfig();
});

/// Per-unit refund base of each line of an order (see
/// `ReturnsRepository.fetchUnitRefunds`), for the line prices and the refund
/// cap. Empty when the order can't be read: the form then shows no amounts
/// and the server checks the cap.
final returnUnitRefundsProvider = FutureProvider.autoDispose
    .family<Map<int, Money>, String>((ref, orderNumber) async {
      try {
        return await ref
            .watch(returnsRepositoryProvider)
            .fetchUnitRefunds(orderNumber);
      } on Object {
        return const <int, Money>{};
      }
    });

/// Finds order [number] among the customer's returnable orders, paging
/// through `hmReturnableOrders` (newest first). With [placedAt] — the order's
/// store-local `order_date` — the search stops at the first page reaching
/// orders a day older than it, since the order can't come after them; it
/// never reads more than [maxPages] pages. Null when the order has nothing
/// returnable.
Future<ReturnableOrder?> findReturnableOrder(
  ReturnsRepository repository,
  String number, {
  String? placedAt,
  int maxPages = 10,
}) async {
  // `order_date` has no offset; read as UTC it is at most a zone offset
  // later than the real instant, so a day of margin covers every zone.
  final placed = placedAt == null
      ? null
      : DateTime.tryParse('${placedAt.trim().replaceFirst(' ', 'T')}Z');
  final floor = placed?.subtract(const Duration(days: 1));
  for (var page = 1; page <= maxPages; page++) {
    final result = await repository.fetchReturnableOrders(currentPage: page);
    for (final order in result.items) {
      if (order.number == number) {
        return order.hasReturnableItem ? order : null;
      }
    }
    if (!result.hasMore || result.items.isEmpty) return null;
    if (floor != null) {
      final oldest = DateTime.tryParse(result.items.last.createdAt);
      if (oldest != null && oldest.isBefore(floor)) return null;
    }
  }
  return null;
}

/// Order [number]'s returnable lines, or null when it has none: drives Return
/// items on the order detail (22), which passes the order's `order_date` so
/// the search stops early (see [findReturnableOrder]).
final returnableOrderProvider = FutureProvider.autoDispose
    .family<ReturnableOrder?, ({String number, String? placedAt})>((
      ref,
      key,
    ) {
      ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
      return findReturnableOrder(
        ref.watch(returnsRepositoryProvider),
        key.number,
        placedAt: key.placedAt,
      );
    });

/// A paged list's state.
class PagedReturnsState<T> {
  const PagedReturnsState({
    this.items = const [],
    this.currentPage = 0,
    this.totalPages = 0,
    this.totalCount = 0,
    this.isLoading = true,
    this.isLoadingMore = false,
    this.error,
  });

  final List<T> items;
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final bool isLoading;
  final bool isLoadingMore;
  final Object? error;

  bool get hasMore => currentPage < totalPages;

  PagedReturnsState<T> copyWith({
    List<T>? items,
    int? currentPage,
    int? totalPages,
    int? totalCount,
    bool? isLoading,
    bool? isLoadingMore,
    Object? error = _keep,
  }) => PagedReturnsState<T>(
    items: items ?? this.items,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    totalCount: totalCount ?? this.totalCount,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: identical(error, _keep) ? this.error : error,
  );

  static const Object _keep = Object();
}

/// Loads a paged list page by page (append on scroll), and again on a
/// store/language switch — labels come in the Store header's language.
abstract class _PagedReturnsController<T>
    extends AutoDisposeNotifier<PagedReturnsState<T>> {
  Future<ReturnsPage<T>> fetchPage(int page);

  @override
  PagedReturnsState<T> build() {
    ref.listen<String>(
      storeControllerProvider.select((s) => s.activeStoreCode),
      (prev, next) {
        if (prev != null && prev != next) Future.microtask(refresh);
      },
    );
    Future.microtask(refresh);
    return PagedReturnsState<T>();
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final page = await fetchPage(1);
      state = state.copyWith(
        items: page.items,
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoading: false,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;
    state = state.copyWith(isLoadingMore: true);
    try {
      final page = await fetchPage(state.currentPage + 1);
      state = state.copyWith(
        items: [...state.items, ...page.items],
        currentPage: page.currentPage,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

/// My returns (23b).
class MyReturnsController extends _PagedReturnsController<ReturnSummary> {
  @override
  Future<ReturnsPage<ReturnSummary>> fetchPage(int page) =>
      ref.read(returnsRepositoryProvider).fetchReturns(currentPage: page);

  /// Opening a return marks it read on the server; mirror that here instead
  /// of reloading the list.
  void markRead(int id) {
    if (!state.items.any((r) => r.id == id && r.hasUnreadReply)) return;
    state = state.copyWith(
      items: [
        for (final r in state.items)
          if (r.id == id)
            ReturnSummary(
              id: r.id,
              number: r.number,
              orderNumber: r.orderNumber,
              createdAt: r.createdAt,
              updatedAt: r.updatedAt,
              state: r.state,
              statusLabel: r.statusLabel,
              type: r.type,
              itemCount: r.itemCount,
              seller: r.seller,
            )
          else
            r,
      ],
    );
  }
}

final myReturnsControllerProvider =
    AutoDisposeNotifierProvider<
      MyReturnsController,
      PagedReturnsState<ReturnSummary>
    >(MyReturnsController.new);

/// The orders the return form (23) offers.
class ReturnableOrdersController
    extends _PagedReturnsController<ReturnableOrder> {
  @override
  Future<ReturnsPage<ReturnableOrder>> fetchPage(int page) => ref
      .read(returnsRepositoryProvider)
      .fetchReturnableOrders(currentPage: page);
}

final returnableOrdersControllerProvider =
    AutoDisposeNotifierProvider<
      ReturnableOrdersController,
      PagedReturnsState<ReturnableOrder>
    >(ReturnableOrdersController.new);

/// One return (23c) and the customer's replies on it.
class ReturnDetailController
    extends AutoDisposeFamilyAsyncNotifier<ReturnDetail?, int> {
  @override
  Future<ReturnDetail?> build(int id) async {
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    final detail = await ref.watch(returnsRepositoryProvider).fetchReturn(id);
    if (detail != null && ref.exists(myReturnsControllerProvider)) {
      ref.read(myReturnsControllerProvider.notifier).markRead(id);
    }
    return detail;
  }

  /// Sends [message] and shows the return as the server returns it. Throws
  /// the [Failure] when the store refuses (a closed return, too long).
  Future<void> reply(String message) async {
    final updated = await ref
        .read(returnsRepositoryProvider)
        .addMessage(arg, message);
    state = AsyncData(updated);
  }
}

final returnDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ReturnDetailController, ReturnDetail?, int>(
      ReturnDetailController.new,
    );

/// Forgets what a new return changes on the screens below the form: My
/// returns and the orders' Return items checks. (The form's own order list
/// goes with the form.)
void invalidateReturnLists(WidgetRef ref) {
  ref.invalidate(myReturnsControllerProvider);
  ref.invalidate(returnableOrderProvider);
}
