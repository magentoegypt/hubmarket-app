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
    this.orderNumber,
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

  /// The customer's own order the transaction records — spent on, refunded,
  /// cancelled or credit bought (`order_number`); null for anything else,
  /// such as the admin's adjustments or a seller's sales.
  final String? orderNumber;

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

/// One fixed amount of credit on sale (`HmStoreCreditPreset`): a fixed-value
/// store credit product, or one value of a dropdown product.
@immutable
class StoreCreditPreset {
  const StoreCreditPreset({
    required this.sku,
    required this.credit,
    required this.price,
  });

  /// Its store credit product.
  final String sku;

  /// Credit added to the balance once the order is invoiced.
  final Money credit;

  /// What the cart line costs.
  final Money price;
}

/// `HmStoreCreditAccount.top_up`: how credit is bought — the store credit
/// products the website's Buy Credit page sells. Fixed amounts are [presets];
/// a custom whole amount from [min] to [max] is allowed when both are set.
@immutable
class StoreCreditTopUp {
  const StoreCreditTopUp({
    required this.sku,
    this.min,
    this.max,
    this.creditRate,
    this.presets = const <StoreCreditPreset>[],
  });

  /// The product a custom amount buys (else the first preset's).
  final String sku;

  /// The custom amount's range; both null when only [presets] can be bought.
  final Money? min;
  final Money? max;

  /// Credit per 1 paid for a custom amount: its price is amount / rate.
  final double? creditRate;

  /// Smallest first.
  final List<StoreCreditPreset> presets;

  bool get allowsCustomAmount => min != null && max != null;

  String get currency =>
      presets.isNotEmpty ? presets.first.credit.currency : min?.currency ?? '';

  /// The preset that sells exactly [amount] of credit, if any.
  StoreCreditPreset? presetFor(double amount) {
    for (final preset in presets) {
      if ((preset.credit.amount - amount).abs() < 0.005) return preset;
    }
    return null;
  }

  /// A whole amount within [min]..[max] — what the website's product page
  /// lets a customer type.
  bool acceptsCustom(double amount) =>
      allowsCustomAmount &&
      amount.isFinite &&
      amount == amount.roundToDouble() &&
      amount >= min!.amount &&
      amount <= max!.amount;

  /// Whether [amount] of credit can be bought: a preset, or a custom amount.
  bool accepts(double amount) =>
      presetFor(amount) != null || acceptsCustom(amount);

  /// What [amount] of credit costs: its preset's price, else amount / rate
  /// in cents; null when it can't be bought.
  Money? priceOf(double amount) {
    final preset = presetFor(amount);
    if (preset != null) return preset.price;
    final rate = creditRate;
    if (!acceptsCustom(amount) || rate == null || rate <= 0) return null;
    return Money(
      amount: (amount / rate * 100).roundToDouble() / 100,
      currency: currency,
    );
  }

  /// The amount chosen when the card opens: the middle preset (Figma 20d's
  /// AED 100 of 50 / 100 / 250), else the smallest custom amount — where the
  /// website's slider starts.
  double? get initialAmount => presets.isNotEmpty
      ? presets[presets.length ~/ 2].credit.amount
      : min?.amount;
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
