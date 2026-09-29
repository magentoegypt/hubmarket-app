import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../../store_credit/presentation/store_credit_providers.dart';
import '../../domain/checkout.dart';
import '../widgets/checkout_parts.dart';
import '../widgets/payment_method_tile.dart';

/// What the order-placed screen shows, handed over by checkout.
class OrderPlacedArgs {
  const OrderPlacedArgs({
    required this.orderNumber,
    this.firstName,
    this.total,
    this.payment,
  });

  final String orderNumber;

  /// The customer's, or the guest's from the delivery address.
  final String? firstName;

  /// The grand total Magento charged.
  final Money? total;
  final PaymentMethodOption? payment;
}

/// 19 Order placed: the tick, the order number, how it is paid, then Track
/// order / Continue shopping. The design's per-store "Arriving in N packages"
/// list waits for store grouping and delivery estimates the backend doesn't
/// provide yet.
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, required this.args});

  final OrderPlacedArgs args;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isEn = Localizations.localeOf(context).languageCode != 'ar';
    final name = args.firstName?.trim() ?? '';
    // The order is placed and the cart gone, so there is nothing to go back
    // to: back (and the close button) leave for Home.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.home);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      color: context.scaffoldHeading,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => context.go(AppRoutes.home),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      const _SuccessTick(),
                      const SizedBox(height: 18),
                      Text(
                        l10n.orderSuccessTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          // Playfair Display has no Arabic glyphs; Arabic keeps
                          // the theme's face.
                          fontFamily: isEn ? AppTheme.displayFont : null,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: context.scaffoldHeading,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        name.isEmpty
                            ? l10n.orderPlacedThanks(args.orderNumber)
                            : l10n.orderPlacedThanksNamed(
                                name,
                                args.orderNumber,
                              ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: context.scaffoldMuted,
                        ),
                      ),
                      if (args.payment != null) ...[
                        const SizedBox(height: 18),
                        _PaymentRow(payment: args.payment!, total: args.total),
                      ],
                      // Store credit the order used (HubAppAccount).
                      _StoreCreditRow(orderNumber: args.orderNumber),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      style: checkoutButtonStyle(context),
                      onPressed: () => context.go(AppRoutes.orders),
                      child: Text(l10n.orderPlacedTrack),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.accentStrong,
                        minimumSize: const Size.fromHeight(52),
                        textStyle: checkoutButtonText(context),
                      ),
                      onPressed: () => context.go(AppRoutes.home),
                      child: Text(l10n.cartContinueShopping),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The green tick in its pale halo.
class _SuccessTick extends StatelessWidget {
  const _SuccessTick();

  @override
  Widget build(BuildContext context) => Container(
    width: 104,
    height: 104,
    alignment: Alignment.center,
    decoration: const BoxDecoration(
      color: AppColors.successSubtle,
      shape: BoxShape.circle,
    ),
    child: Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.successStrong,
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check, size: 36, color: Colors.white),
    ),
  );
}

/// "AED 23.00 paid with your store credit" under the payment line, read from
/// the placed order (`OrderTotal.hm_store_credit`); nothing while store credit
/// is off or the order used none.
class _StoreCreditRow extends ConsumerWidget {
  const _StoreCreditRow({required this.orderNumber});

  final String orderNumber;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credit = ref.watch(orderStoreCreditProvider(orderNumber)).valueOrNull;
    if (credit == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.isDarkMode ? Colors.white10 : AppColors.successSubtle,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.card_giftcard_outlined,
              size: 20,
              color: context.isDarkMode
                  ? AppColors.success
                  : AppColors.successStrong,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                // An isolate keeps "AED 23.00" in order inside Arabic.
                l10n.orderPlacedPaidWithCredit(
                  '\u2066${credit.formatted()}\u2069',
                ),
                style: TextStyle(fontSize: 14, color: context.scaffoldHeading),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How the order is paid. Every method checkout offers settles on delivery or
/// needs no payment, so there is no "Paid" state to show yet.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.total});

  final PaymentMethodOption payment;
  final Money? total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // An isolate keeps "AED 553.00" in order inside an Arabic sentence.
    final amount = '\u2066${total?.formatted()}\u2069';
    final String text;
    if (payment.isFree) {
      text = l10n.checkoutFreeOrder;
    } else if (total == null) {
      text = payment.title;
    } else if (payment.isCashOnDelivery) {
      text = l10n.orderPlacedPayOnDelivery(amount);
    } else {
      text = l10n.orderPlacedPayWith(amount, payment.title);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDarkMode ? Colors.white10 : AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            paymentMethodIcon(payment),
            size: 20,
            color: context.scaffoldHeading,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 14, color: context.scaffoldHeading),
            ),
          ),
        ],
      ),
    );
  }
}
