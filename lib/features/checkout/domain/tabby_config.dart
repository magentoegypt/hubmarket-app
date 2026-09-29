import '../../catalog/domain/money.dart';

/// Tabby products, matching `TabbyProductType` in the backend contract.
enum TabbyProductType { installments, payLater, creditCardInstallments }

extension TabbyProductTypeX on TabbyProductType {
  /// Equal payments for the promo: "Pay in 4" → 4; "Pay Later" → 1; card
  /// instalments vary by issuer (unknown here) → null (generic message).
  int? get installmentCount => switch (this) {
    TabbyProductType.installments => 4,
    TabbyProductType.payLater => 1,
    TabbyProductType.creditCardInstallments => null,
  };
}

/// One Tabby product's backend config — enable flag, thresholds (AED) and the
/// promo toggle. All values come from Magento; nothing is hardcoded.
class TabbyProduct {
  const TabbyProduct({
    required this.type,
    required this.methodCode,
    required this.enabled,
    required this.promoEnabled,
    this.minAmount,
    this.maxAmount,
  });

  final TabbyProductType type;

  /// tabby_installments | tabby_cc_installments | tabby_checkout.
  final String methodCode;
  final bool enabled;

  /// product_promotions (PDP) / cart_promotions — whether to show the promo.
  final bool promoEnabled;

  /// Inclusive AED bounds; null means unbounded on that side.
  final double? minAmount;
  final double? maxAmount;

  bool _inRange(Money price, String currency) {
    if (price.currency != currency) return false;
    if (minAmount != null && price.amount < minAmount!) return false;
    if (maxAmount != null && price.amount > maxAmount!) return false;
    return true;
  }

  bool isEligible(Money price, String currency) =>
      enabled && _inRange(price, currency);

  bool isPromoEligible(Money price, String currency) =>
      enabled && promoEnabled && _inRange(price, currency);

  /// Per-instalment amount for the promo (null when the count is unknown).
  Money? perInstallment(Money price) {
    final count = type.installmentCount;
    if (count == null || count <= 1) return null;
    return Money(amount: price.amount / count, currency: price.currency);
  }
}

/// Tabby eligibility + promo metadata for the store, resolved **entirely from
/// backend config** (`tabbyConfig`). Eligibility/promo only — checkout
/// availability still comes from `cart { available_payment_methods }`.
class TabbyConfig {
  const TabbyConfig({
    required this.enabled,
    required this.currency,
    this.publishableKey,
    this.merchantCode,
    this.products = const [],
  });

  final bool enabled;
  final String currency;
  final String? publishableKey;
  final String? merchantCode;
  final List<TabbyProduct> products;

  /// Enabled, in-range products whose promo is on — one promo line per entry.
  List<TabbyProduct> promoFor(Money price) => enabled
      ? products.where((p) => p.isPromoEligible(price, currency)).toList()
      : const [];

  TabbyProduct? product(TabbyProductType type) {
    for (final p in products) {
      if (p.type == type) return p;
    }
    return null;
  }
}
