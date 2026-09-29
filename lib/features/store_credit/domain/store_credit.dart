import 'package:flutter/foundation.dart';

import '../../catalog/domain/money.dart';
import '../../checkout/domain/checkout.dart';

/// What a transaction did to the balance, from the Vnecoms Credit processor
/// code (`HmStoreCreditTransaction.type`). Picks the row's icon on 20d; the
/// words come from the server's own `type_label`.
enum StoreCreditTransactionKind {
  /// `spend_credit`: used at checkout.
  spent,

  /// `refund_by_credit` (a refund paid into credit) and `refund_spent_credit`
  /// (credit given back when an order that used it is refunded).
  refunded,

  /// `buy_credit`, `admin_add_credit`, and any other code that adds credit
  /// (seller commissions share the ledger).
  added,

  /// `admin_subtract_credit`, and any other code that takes credit away.
  deducted,
}

/// One line of `hmStoreCredit.transactions`, newest first.
@immutable
class StoreCreditTransaction {
  const StoreCreditTransaction({
    required this.id,
    required this.type,
    required this.typeLabel,
    required this.amount,
    required this.balanceAfter,
    this.description,
    this.createdAt = '',
  });

  final int id;

  /// Processor code, e.g. `spend_credit`.
  final String type;

  /// The processor's title in the store view's language.
  final String typeLabel;

  /// Signed: positive adds to the balance, negative takes from it.
  final Money amount;
  final Money balanceAfter;

  /// Plain text, e.g. the order it was used on; null when there is none.
  final String? description;

  /// ISO-8601 UTC (`2026-09-26T08:14:00Z`); empty when unknown.
  final String createdAt;

  bool get isCredit => amount.amount > 0;

  /// [amount] without its sign, for "+ AED 43.00" / "− AED 23.00".
  Money get magnitude =>
      Money(amount: amount.amount.abs(), currency: amount.currency);

  StoreCreditTransactionKind get kind => switch (type) {
    'spend_credit' => StoreCreditTransactionKind.spent,
    'refund_by_credit' ||
    'refund_spent_credit' => StoreCreditTransactionKind.refunded,
    'admin_subtract_credit' => StoreCreditTransactionKind.deducted,
    _ =>
      amount.amount < 0
          ? StoreCreditTransactionKind.deducted
          : StoreCreditTransactionKind.added,
  };
}

/// `hmStoreCredit`: the balance and one page of transactions — or several
/// pages appended, as 20d scrolls.
@immutable
class StoreCreditAccount {
  const StoreCreditAccount({
    required this.balance,
    required this.canUseAtCheckout,
    this.transactions = const <StoreCreditTransaction>[],
    this.totalCount = 0,
    this.currentPage = 1,
    this.totalPages = 1,
  });

  final Money balance;

  /// The website's rule (`credit/general/credit_group`): the customer's group
  /// may spend credit. Off for everyone while that setting is empty.
  final bool canUseAtCheckout;
  final List<StoreCreditTransaction> transactions;
  final int totalCount;
  final int currentPage;
  final int totalPages;

  bool get hasMore => currentPage < totalPages;

  /// This account with [next]'s transactions after its own and [next]'s
  /// balance and paging (the newest answer wins).
  StoreCreditAccount append(StoreCreditAccount next) => StoreCreditAccount(
    balance: next.balance,
    canUseAtCheckout: next.canUseAtCheckout,
    transactions: [
      ...transactions,
      for (final t in next.transactions)
        if (!transactions.any((have) => have.id == t.id)) t,
    ],
    totalCount: next.totalCount,
    currentPage: next.currentPage,
    totalPages: next.totalPages,
  );
}

/// `Cart.hm_store_credit`: the credit on the signed-in customer's cart.
@immutable
class CartStoreCredit {
  const CartStoreCredit({
    required this.applied,
    required this.balance,
    required this.maxApplicable,
    required this.canUse,
  });

  /// Credit used on the cart right now (0 when none).
  final Money applied;

  /// The account balance.
  final Money balance;

  /// What can be used: the balance, capped at the order total (subtotal after
  /// discount + shipping + tax).
  final Money maxApplicable;

  /// The customer's group may spend credit.
  final bool canUse;

  bool get isApplied => applied.amount > 0.0001;

  /// Checkout offers "Use my credit" when the customer may spend credit and
  /// there is some to use on this order — or some already used to take back.
  bool get offered => canUse && (isApplied || maxApplicable.amount > 0.0001);
}

/// The cart as `hmApplyStoreCredit` / `hmRemoveStoreCredit` left it: its
/// credit, what it costs now, and the methods that can pay for that — a
/// total the credit covers leaves Magento offering only Zero Subtotal
/// Checkout.
@immutable
class StoreCreditCartUpdate {
  const StoreCreditCartUpdate({
    this.credit,
    this.grandTotal,
    this.paymentMethods,
  });

  final CartStoreCredit? credit;
  final Money? grandTotal;

  /// Null when the answer didn't list them.
  final List<PaymentMethodOption>? paymentMethods;
}
