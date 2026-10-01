import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp_models.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../core/widgets/hub_icon_button.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/cart.dart';
import '../../../catalog/domain/money.dart';
import '../../../marketplace/domain/seller_groups.dart';
import '../../../marketplace/presentation/seller_widgets.dart';
import '../../../store_credit/presentation/store_credit_providers.dart';
import '../../domain/checkout.dart';
import '../widgets/payment_method_tile.dart';

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
  const PlacedPackage({
    required this.seller,
    required this.itemCount,
    this.imageUrls = const <String?>[],
  });

  /// Null for lines the backend named no seller for.
  final HmSellerSummary? seller;

  /// Units of the store's lines.
  final int itemCount;

  /// One photo per line of the store, in the cart's order (null for a line
  /// without one) — the thumbnails at the end of the package's row.
  final List<String?> imageUrls;
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
      imageUrls: [for (final item in group.items) item.imageUrl],
    ),
];

/// 19 Order placed: the tick, the order number, "Arriving in N packages" with
/// the stores the order ships from and thumbnails of what they send (HubApp),
/// how it is paid, then Track order (this order) / Continue shopping. The
/// frame's per-package delivery estimates need data the backend doesn't
/// provide yet, so a package row carries no arrival line.
class OrderSuccessScreen extends StatelessWidget {
  const OrderSuccessScreen({super.key, required this.args});

  final OrderPlacedArgs args;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final name = args.firstName?.trim() ?? '';
    // Figma "Body": the buttons sit 30 px above the bottom edge — the device's
    // home-indicator inset when that is larger.
    final bottom = math.max(30.0, MediaQuery.paddingOf(context).bottom);
    // The order is placed and the cart gone, so there is nothing to go back
    // to: back (and the close button) leave for Home.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.home);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              SizedBox(
                height: 56,
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: HubIconButton(
                      icon: HubIcons.x,
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: _SuccessTick()),
                      const SizedBox(height: 18),
                      Text(
                        l10n.orderSuccessTitle,
                        textAlign: TextAlign.center,
                        style: t.display.copyWith(
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
                        style: t.body.copyWith(color: context.scaffoldMuted),
                      ),
                      if (args.packages.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        _PackagesBlock(packages: args.packages),
                      ],
                      if (args.payment != null) ...[
                        const SizedBox(height: 18),
                        _PaymentRow(payment: args.payment!, total: args.total),
                      ],
                      // Store credit the order used (HubAppAccount).
                      _StoreCreditRow(orderNumber: args.orderNumber),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // This order, with My Orders beneath it.
                    HubButton(
                      label: l10n.orderPlacedTrack,
                      onPressed: () =>
                          context.go(AppRoutes.orderByNumber(args.orderNumber)),
                    ),
                    const SizedBox(height: 18),
                    HubButton(
                      label: l10n.cartContinueShopping,
                      style: HubButtonStyle.ghost,
                      onPressed: () => context.go(AppRoutes.home),
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
    final t = AppTextStyles.of(context);
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
                style: t.body.copyWith(color: context.scaffoldHeading),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// How the order is paid (Figma "payment": a muted card, the method's icon and
/// a sentence). Every method checkout offers settles on delivery or needs no
/// payment, so there is no "Paid" badge to show yet.
class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.total});

  final PaymentMethodOption payment;
  final Money? total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
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
              style: t.body.copyWith(color: context.scaffoldHeading),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Arriving in 2 packages" and the card under it: one row per store the order
/// ships from — its logo, its name, and thumbnails of what it sends — with a
/// hairline between stores.
class _PackagesBlock extends StatelessWidget {
  const _PackagesBlock({required this.packages});

  final List<PlacedPackage> packages;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.orderPlacedPackages(packages.length),
          style: t.title.copyWith(color: context.scaffoldHeading),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.isDarkMode
                  ? Colors.white24
                  : AppColors.borderSubtle,
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < packages.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: context.isDarkMode
                        ? Colors.white24
                        : AppColors.borderSubtle,
                  ),
                _PackageRow(index: i + 1, package: packages[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.index, required this.package});

  /// 1-based, as the order detail numbers its packages.
  final int index;
  final PlacedPackage package;

  /// Thumbnails per package; a store with more lines shows "+N".
  static const int maxThumbnails = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final seller = package.seller;
    final shown = package.imageUrls.take(maxThumbnails).toList();
    final more = package.imageUrls.length - shown.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          if (seller != null)
            SellerLogo(seller: seller, size: 36)
          else
            SizedBox(
              width: 36,
              child: Icon(
                HubIcons.package,
                size: 20,
                color: context.scaffoldMuted,
              ),
            ),
          const SizedBox(width: 12),
          // The name gives way (ellipsis) to the thumbnails.
          Expanded(
            child: Text(
              seller?.name ?? l10n.orderPackageTitleNoStore(index),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodyStrong.copyWith(color: context.scaffoldHeading),
            ),
          ),
          const SizedBox(width: 12),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            HubImage(
              url: shown[i],
              width: 40,
              height: 40,
              borderRadius: BorderRadius.circular(8),
              placeholder: (_) =>
                  const ColoredBox(color: AppColors.surfaceSubtle),
              error: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
            ),
          ],
          if (more > 0) ...[
            const SizedBox(width: 6),
            Text(
              '+$more',
              textDirection: TextDirection.ltr,
              style: t.caption.copyWith(color: context.scaffoldMuted),
            ),
          ],
        ],
      ),
    );
  }
}
