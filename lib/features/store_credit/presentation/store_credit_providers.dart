import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/hubapp_account.dart';
import '../../../core/error/failure.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../catalog/domain/money.dart';
import '../data/store_credit_repository.dart';
import '../domain/store_credit.dart';

/// Store credit is on: the server has it (`HubAppAccount`) and a customer is
/// signed in — credit belongs to an account.
final storeCreditEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(hubAppAccountFeaturesProvider.select((f) => f.storeCredit)) &&
      ref.watch(authControllerProvider.select((a) => a.isAuthenticated)),
);

/// Remembers that the server turned out not to have the account module, so
/// every store-credit entry point hides for the rest of the session.
void markHubAppAccountMissing(Ref ref) =>
    ref.read(hubAppAccountMissingProvider.notifier).mark();

/// The balance behind Account's "My credit" row (Figma 20). Null while store
/// credit is off or once the server shows it doesn't have the module.
final storeCreditBalanceProvider =
    FutureProvider.autoDispose<StoreCreditAccount?>((ref) async {
      if (!ref.watch(storeCreditEnabledProvider)) return null;
      try {
        return await ref.watch(storeCreditRepositoryProvider).fetchBalance();
      } on HubAppMissing {
        markHubAppAccountMissing(ref);
        return null;
      }
    });

/// The credit order [orderNumber] was paid with (`OrderTotal.hm_store_credit`)
/// for order detail and order placed; null when it used none, when store
/// credit is off, or when the lookup fails — the line is one detail of an
/// order that shows either way.
final orderStoreCreditProvider = FutureProvider.autoDispose
    .family<Money?, String>((ref, orderNumber) async {
      if (!ref.watch(storeCreditEnabledProvider)) return null;
      try {
        return await ref
            .watch(storeCreditRepositoryProvider)
            .fetchOrderCredit(orderNumber);
      } on HubAppMissing {
        markHubAppAccountMissing(ref);
        return null;
      } on Failure {
        return null;
      }
    });

/// 20d My credit: the account and every page of transactions loaded so far.
@immutable
class MyCreditState {
  const MyCreditState({required this.account, this.loadingMore = false});

  final StoreCreditAccount account;

  /// The next page is on its way (the list's footer spinner).
  final bool loadingMore;
}

class MyCreditController extends AutoDisposeAsyncNotifier<MyCreditState> {
  StoreCreditRepository get _repo => ref.read(storeCreditRepositoryProvider);

  @override
  Future<MyCreditState> build() async {
    try {
      final account = await ref
          .watch(storeCreditRepositoryProvider)
          .fetchAccount();
      return MyCreditState(account: account);
    } on HubAppMissing {
      markHubAppAccountMissing(ref);
      rethrow;
    }
  }

  /// Appends the next page of transactions. A failure keeps what is shown;
  /// the next scroll to the end tries again.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.account.hasMore) {
      return;
    }
    state = AsyncData(
      MyCreditState(account: current.account, loadingMore: true),
    );
    try {
      final next = await _repo.fetchAccount(
        currentPage: current.account.currentPage + 1,
      );
      state = AsyncData(MyCreditState(account: current.account.append(next)));
    } on Object {
      state = AsyncData(MyCreditState(account: current.account));
    }
  }
}

final myCreditControllerProvider =
    AsyncNotifierProvider.autoDispose<MyCreditController, MyCreditState>(
      MyCreditController.new,
    );
