import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../l10n/l10n.dart';
import '../../catalog/domain/money.dart';
import '../data/checkout_repository.dart';
import '../domain/tabby_config.dart';

/// Backend-resolved Tabby config. Rebuilds (refetches) when the GraphQL client is
/// reset on a store switch, since thresholds/currency are store-scoped.
final tabbyConfigProvider = FutureProvider<TabbyConfig?>(
  (ref) => ref.watch(checkoutRepositoryProvider).fetchTabbyConfig(),
);

/// Tabby promo ("Pay in 4" / "Pay Later"), shown on the PDP and cart **only for
/// the products the backend enables and the price qualifies for** — one line per
/// eligible product. Renders nothing otherwise; no fabricated eligibility.
class TabbyPromo extends ConsumerWidget {
  const TabbyPromo({super.key, required this.price, this.padding});

  final Money price;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(tabbyConfigProvider).valueOrNull;
    final eligible = config?.promoFor(price) ?? const <TabbyProduct>[];
    if (eligible.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    // A bordered, tappable promo card (QA: the widget was non-clickable) — one
    // line per eligible Tabby product, opening an explainer sheet on tap.
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: InkWell(
        onTap: () => _showInfo(context, l10n),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceTint,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            children: [
              const _TabbyChip(),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final product in eligible)
                      Text(
                        _message(l10n, product),
                        style: const TextStyle(
                          color: AppColors.inkHeading,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.info_outline,
                size: 18,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, AppLocalizations l10n) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TabbyInfoSheet(l10n: l10n),
    );
  }

  String _message(AppLocalizations l10n, TabbyProduct product) {
    final per = product.perInstallment(price);
    return switch (product.type) {
      TabbyProductType.installments when per != null => l10n.promoTabbyPayIn4(
        product.type.installmentCount ?? 4,
        per.formatted(),
      ),
      TabbyProductType.installments => l10n.promoTabbyPayLater,
      TabbyProductType.payLater => l10n.promoTabbyPayLater,
      TabbyProductType.creditCardInstallments => l10n.promoTabbyCardInstalments,
    };
  }
}

class _TabbyChip extends StatelessWidget {
  const _TabbyChip();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0xFF3EE6C3),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Text(
      'tabby',
      style: TextStyle(
        color: Colors.black,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    ),
  );
}

/// Bottom-sheet explainer opened from [TabbyPromo] (QA: make the widget
/// actionable). Copy-only — the real eligibility/checkout still flow through
/// `available_payment_methods` at checkout.
class _TabbyInfoSheet extends StatelessWidget {
  const _TabbyInfoSheet({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _TabbyChip(),
            const SizedBox(height: 14),
            Text(
              l10n.tabbyInfoTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.inkHeading,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.tabbyInfoBody,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.tabbyInfoGotIt),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
