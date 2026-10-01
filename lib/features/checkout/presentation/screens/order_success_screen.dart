import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/cart.dart';
import '../../../catalog/domain/money.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../../store_credit/presentation/store_credit_providers.dart';
import '../../domain/checkout.dart';
import '../widgets/checkout_parts.dart';
import '../widgets/payment_method_tile.dart';
import '../../../../app/theme/hub_icons.dart';

/// What the order-placed screen shows, handed over by checkout.
class OrderPlacedArgs {
  const OrderPlacedArgs({
    required this.orderNumber,
    this.firstName,
    this.total,
    this.payment,
    this.packages = const <PlacedPackage>[],
  });

  final String orderNumber;

  /// The customer's, or the guest's from the delivery address.
  final String? firstName;

  /// The grand total Magento charged.
  final Money? total;
  final PaymentMethodOption? payment;

  /// One per store the order ships from ([placedPackagesOf]); empty without
  /// HubApp, whose cart lines name no seller.
  final List<PlacedPackage> packages;
}

/// One store's share of a placed order — a package of its own when it ships.
class PlacedPackage {
  const PlacedPackage({required this.seller, required this.itemCount});

  /// Null for lines the backend named no seller for.
  final HmSellerSummary? seller;

  /// Units of the store's lines.
  final int itemCount;
}

/// The stores [cart] ships from, read from its lines' `hm_seller` before
/// `placeOrder` consumes it — in the order the cart groups them (Figma 16).
/// Empty when no line names a seller (Build 1).
List<PlacedPackage> placedPackagesOf(Cart cart) => [
  for (final group
      in groupBySeller<CartItem>(cart.items, (item) => item.seller) ??
          const <SellerGroup<CartItem>>[])
    PlacedPackage(
      seller: group.seller,
      itemCount: group.items.fold(0, (sum, item) => sum + item.quantity),
    ),
];

/// 19 Order placed: the tick, the order number, how it is paid, "Arriving in
/// N packages" with the stores the order ships from (HubApp), then Track
/// order (this order) / Continue shopping. The frame's per-package delivery
/// estimates need data the backend doesn't provide yet.
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
                      icon: const Icon(HubIcons.x, size: 22),
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
                      if (args.packages.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _PackagesCard(packages: args.packages),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // This order, with My Orders beneath it.
                    FilledButton(
                      style: checkoutButtonStyle(context),
                      onPressed: () => context.go(
                        AppRoutes.orderByNumber(args.orderNumber),
                      ),
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
      child: const Icon(HubIcons.check, size: 36, color: Colors.white),
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
              HubIcons.gift,
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

/// "Arriving in 2 packages": one row per store the order ships from — its
/// logo, name and ✓, and how many items it sends.
class _PackagesCard extends StatelessWidget {
  const _PackagesCard({required this.packages});

  final List<PlacedPackage> packages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: context.isDarkMode ? Colors.white10 : AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                HubIcons.package,
                size: 20,
                color: context.scaffoldHeading,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.orderPlacedPackages(packages.length),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.scaffoldHeading,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < packages.length; i++)
            _PackageRow(index: i + 1, package: packages[i]),
        ],
      ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.index, required this.package});

  /// 1-based, as the order detail numbers its packages.
  final int index;
  final PlacedPackage package;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final seller = package.seller;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          if (seller != null)
            SellerLogo(seller: seller)
          else
            SizedBox(
              width: 28,
              child: Icon(
                HubIcons.package,
                size: 18,
                color: context.scaffoldMuted,
              ),
            ),
          const SizedBox(width: 10),
          // The name gives way (ellipsis) to the item count.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    seller?.name ?? l10n.orderPackageTitleNoStore(index),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.scaffoldHeading,
                    ),
                  ),
                ),
                if (seller != null && !seller.isMarketplace) ...[
                  const SizedBox(width: 6),
                  const SellerVerifiedIcon(),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.orderItemCount(package.itemCount),
            style: TextStyle(fontSize: 12, color: context.scaffoldMuted),
          ),
        ],
      ),
    );
  }
}
