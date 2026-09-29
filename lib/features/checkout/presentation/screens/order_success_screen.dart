import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes.dart';
import '../../../../app/shell/hub_bottom_nav.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../l10n/l10n.dart';
import '../../../auth/presentation/auth_controller.dart';

class OrderSuccessScreen extends ConsumerWidget {
  const OrderSuccessScreen({
    super.key,
    required this.orderNumber,
    this.pendingPayment = false,
    this.deliveryEta,
    this.deliveryLocation,
  });

  final String orderNumber;
  final bool pendingPayment;

  /// Shipping-method label for the delivery chip (e.g. "Standard Shipping").
  final String? deliveryEta;

  /// Emirate the order ships to (delivery chip).
  final String? deliveryLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // Awaiting-payment orders get a neutral gold "received" treatment, not the
    // celebratory navy check reserved for a confirmed order.
    final accent = pendingPayment
        ? AppColors.accentGold
        : AppColors.brandPrimary;
    final firstName = ref.watch(authControllerProvider).customer?.firstName ?? '';

    // Delivery chip from real data (shipping method + emirate); hidden for
    // awaiting-payment orders or when neither is known.
    final chipText = [
      if (deliveryEta != null && deliveryEta!.isNotEmpty) deliveryEta!,
      if (deliveryLocation != null && deliveryLocation!.isNotEmpty)
        deliveryLocation!,
    ].join(' · ');
    final showChip = !pendingPayment && chipText.isNotEmpty;

    return Scaffold(
      // Figma: centered HUB MARKET lockup + a close (×) to leave the success flow.
      appBar: AppBar(
        toolbarHeight: 60,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 4,
        title: const BrandLogo(height: 44),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.go(AppRoutes.home),
          ),
        ],
      ),
      bottomNavigationBar: const HubBottomNav(current: AppTab.home),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Rounded-rectangle (squircle) badge with a white check.
                    Container(
                      width: 88,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        color: accent,
                      ),
                      child: Icon(
                        pendingPayment ? Icons.schedule : Icons.check,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      pendingPayment
                          ? l10n.orderPendingTitle
                          : l10n.orderSuccessTitle,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      firstName.isEmpty
                          ? l10n.orderSuccessThanks
                          : l10n.orderSuccessThanksNamed(firstName),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 20),
                    _OrderNumberCard(orderNumber: orderNumber),
                    if (showChip) ...[
                      const SizedBox(height: 12),
                      _DeliveryChip(text: chipText),
                    ],
                    if (pendingPayment) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.paymentRedirectPending,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.inkMuted),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.go(AppRoutes.orders),
                        icon: const Icon(Icons.local_shipping_outlined, size: 18),
                        label: Text(l10n.footerTrackOrder),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.go(AppRoutes.home),
                        child: Text(l10n.cartContinueShopping),
                      ),
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

/// Blush pill with a truck icon — the delivery method + destination emirate.
class _DeliveryChip extends StatelessWidget {
  const _DeliveryChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.local_shipping_outlined,
          size: 18,
          color: AppColors.brandPrimary,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.brandPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Order-number card with a copy action.
class _OrderNumberCard extends StatelessWidget {
  const _OrderNumberCard({required this.orderNumber});
  final String orderNumber;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.orderNumberLabel,
                  style: const TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '#$orderNumber',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkHeading,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: orderNumber));
              messenger.showSnackBar(
                SnackBar(content: Text(l10n.orderNumberCopied)),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(l10n.actionCopy),
          ),
        ],
      ),
    );
  }
}
