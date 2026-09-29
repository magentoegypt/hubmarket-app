import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/features/catalog/domain/money.dart';
import 'package:hubmarket_app/features/checkout/domain/checkout.dart';
import 'package:hubmarket_app/features/store_credit/data/store_credit_repository.dart';
import 'package:hubmarket_app/features/store_credit/domain/store_credit.dart';

import 'hubapp_fakes.dart';

/// Test doubles for `HubAppAccount`: the probe with the account switches as a
/// test wants them, and a store-credit repository serving canned pages and
/// cart credit and recording every call.

/// `hmAppConfig` with the HubAppAccount switches as given.
HmAppConfig hubAppAccountConfig({
  bool storeCredit = false,
  bool push = false,
  bool whatsappLogin = false,
}) => HmAppConfig(
  storeCode: 'en',
  locale: 'en_US',
  features: {
    'store_credit': storeCredit,
    'push': push,
    'whatsapp_login': whatsappLogin,
  },
);

/// The HubApp probe with the module deployed and the account switches as
/// given — or, with [deployed] false, a server without the module.
Override accountHubApp({
  bool deployed = true,
  bool storeCredit = true,
  bool push = false,
  bool whatsappLogin = false,
}) => hubAppOverride(
  deployed
      ? HubAppState.available(
          hubAppAccountConfig(
            storeCredit: storeCredit,
            push: push,
            whatsappLogin: whatsappLogin,
          ),
        )
      : const HubAppState.unavailable(),
);

Money aedCredit(double amount) => Money(amount: amount, currency: 'AED');

/// The three transactions of Figma 20d, newest first.
List<StoreCreditTransaction> sampleCreditTransactions({bool arabic = false}) =>
    [
      StoreCreditTransaction(
        id: 31,
        type: 'refund_by_credit',
        typeLabel: arabic ? 'استرداد إلى الرصيد' : 'Refund to credit',
        amount: aedCredit(43),
        balanceAfter: aedCredit(120),
        description: arabic
            ? 'إرجاع #R-000031 · تيشيرت قصير ياقة مربع'
            : 'Return #R-000031 · Short Square-Neck T-Shirt',
        createdAt: '2026-09-26T08:14:00Z',
      ),
      StoreCreditTransaction(
        id: 30,
        type: 'spend_credit',
        typeLabel: arabic ? 'استخدام عند الدفع' : 'Used at checkout',
        amount: aedCredit(-23),
        balanceAfter: aedCredit(77),
        description: arabic
            ? 'طلب \u200E#000000231'
            : 'Spent credit on order #000000231',
        createdAt: '2026-09-20T11:02:00Z',
      ),
      StoreCreditTransaction(
        id: 29,
        type: 'admin_add_credit',
        typeLabel: arabic ? 'رصيد مضاف' : 'Credit added',
        amount: aedCredit(100),
        balanceAfter: aedCredit(100),
        description: arabic ? 'إضافة من هب ماركت' : 'Added by Hub Market',
        createdAt: '2026-09-02T09:30:00Z',
      ),
    ];

/// A signed-in customer's credit with the Figma 20d balance.
StoreCreditAccount sampleCreditAccount({
  bool canUse = true,
  bool arabic = false,
  List<StoreCreditTransaction>? transactions,
  int currentPage = 1,
  int totalPages = 1,
}) {
  final list = transactions ?? sampleCreditTransactions(arabic: arabic);
  return StoreCreditAccount(
    balance: aedCredit(120),
    canUseAtCheckout: canUse,
    transactions: list,
    totalCount: list.length,
    currentPage: currentPage,
    totalPages: totalPages,
  );
}

/// Cart credit as the payment step reads it: AED 120 balance on a cart that
/// costs more, nothing used yet.
CartStoreCredit sampleCartCredit({
  double applied = 0,
  double balance = 120,
  double maxApplicable = 120,
  bool canUse = true,
}) => CartStoreCredit(
  applied: aedCredit(applied),
  balance: aedCredit(balance),
  maxApplicable: aedCredit(maxApplicable),
  canUse: canUse,
);

class FakeStoreCreditRepository implements StoreCreditRepository {
  FakeStoreCreditRepository({
    List<StoreCreditAccount>? pages,
    this.cartCredit,
    this.grandTotalBefore = 553,
    this.paymentMethods = const [
      PaymentMethodOption(code: 'cashondelivery', title: 'Cash on delivery'),
    ],
    this.paymentMethodsWhenCovered = const [
      PaymentMethodOption(
        code: 'free',
        title: 'No Payment Information Required',
      ),
    ],
    this.orderCredits = const <String, Money>{},
  }) : pages = pages ?? [sampleCreditAccount()];

  /// Served by [fetchAccount] per `currentPage` (1-based).
  final List<StoreCreditAccount> pages;

  /// The cart's credit; [apply] / [remove] move it.
  CartStoreCredit? cartCredit;

  /// The cart total before any credit.
  final double grandTotalBefore;

  /// What the cart offers while it still costs something, and once credit
  /// covers all of it.
  final List<PaymentMethodOption> paymentMethods;
  final List<PaymentMethodOption> paymentMethodsWhenCovered;

  final Map<String, Money> orderCredits;

  /// Every call, in order: `fetchAccount:1`, `apply:cart-1:120.0`, …
  final List<String> calls = [];

  /// Thrown by the next call when set (and then cleared).
  Object? nextError;

  /// Every call throws [HubAppMissing] — the server lacks the module.
  bool missing = false;

  Future<void> _gate(String call) async {
    calls.add(call);
    if (missing) {
      throw const HubAppMissing(
        'Cannot query field "hmStoreCredit" on type "Query".',
      );
    }
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }

  @override
  Future<StoreCreditAccount> fetchAccount({
    int pageSize = StoreCreditRepository.pageSize,
    int currentPage = 1,
  }) async {
    await _gate('fetchAccount:$currentPage');
    return pages[currentPage - 1];
  }

  @override
  Future<StoreCreditAccount> fetchBalance() async {
    await _gate('fetchBalance');
    final first = pages.first;
    return StoreCreditAccount(
      balance: first.balance,
      canUseAtCheckout: first.canUseAtCheckout,
    );
  }

  @override
  Future<CartStoreCredit?> fetchCartCredit(String cartId) async {
    await _gate('fetchCartCredit:$cartId');
    return cartCredit;
  }

  @override
  Future<StoreCreditCartUpdate> apply(String cartId, double amount) async {
    await _gate('apply:$cartId:$amount');
    final current = cartCredit ?? sampleCartCredit();
    final used = amount.clamp(0, grandTotalBefore).toDouble();
    cartCredit = CartStoreCredit(
      applied: aedCredit(used),
      balance: current.balance,
      maxApplicable: current.maxApplicable,
      canUse: current.canUse,
    );
    return _update();
  }

  @override
  Future<StoreCreditCartUpdate> remove(String cartId) async {
    await _gate('remove:$cartId');
    final current = cartCredit ?? sampleCartCredit();
    cartCredit = CartStoreCredit(
      applied: aedCredit(0),
      balance: current.balance,
      maxApplicable: current.maxApplicable,
      canUse: current.canUse,
    );
    return _update();
  }

  /// The cart's total after the credit now on it.
  double get grandTotalNow =>
      grandTotalBefore - (cartCredit?.applied.amount ?? 0);

  StoreCreditCartUpdate _update() => StoreCreditCartUpdate(
    credit: cartCredit,
    grandTotal: aedCredit(grandTotalNow),
    paymentMethods: grandTotalNow <= 0.0001
        ? paymentMethodsWhenCovered
        : paymentMethods,
  );

  @override
  Future<Money?> fetchOrderCredit(String orderNumber) async {
    await _gate('fetchOrderCredit:$orderNumber');
    return orderCredits[orderNumber];
  }
}

/// A store refusal worded the way the backend words it.
const Failure kCreditRefused = Failure(
  FailureKind.server,
  detail: 'You can use at most AED 120.00 of store credit.',
);
