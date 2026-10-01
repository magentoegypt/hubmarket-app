import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/hub_button.dart';
import '../../../../l10n/l10n.dart';

/// What the shopper chose on the "Payment declined" sheet.
enum PaymentFailedAction {
  /// Back to the payment step to pick another method.
  tryAnotherMethod,

  /// Switch the order to cash on delivery.
  payCashOnDelivery,

  /// Leave checkout for the cart.
  backToCart,
}

/// Opens the "Payment declined" sheet (Figma S5) over the page, with the
/// design's scrim (navy at 55 %). Resolves to the shopper's choice, or null when
/// the sheet is dismissed.
Future<PaymentFailedAction?> showPaymentFailedSheet(
  BuildContext context, {
  required String methodTitle,
  String? reason,
  bool canTryAnotherMethod = false,
  bool canPayCashOnDelivery = false,
}) => showModalBottomSheet<PaymentFailedAction>(
  context: context,
  backgroundColor: Colors.white,
  barrierColor: const Color(0x8C0F2144),
  isScrollControlled: true,
  useSafeArea: false,
  clipBehavior: Clip.antiAlias,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  // The sheet is a light surface in dark mode too, as the checkout page is, so
  // it carries the light theme (the route is built outside the page's Theme).
  builder: (sheetContext) => Theme(
    data: AppTheme.light(Localizations.localeOf(sheetContext).languageCode),
    child: PaymentFailedSheet(
      methodTitle: methodTitle,
      reason: reason,
      canTryAnotherMethod: canTryAnotherMethod,
      canPayCashOnDelivery: canPayCashOnDelivery,
    ),
  ),
);

/// Figma S5 "Payment failed": a bottom sheet with the red alert disc, what
/// happened and that nothing was charged, the reason the store gave, and the
/// ways on — another method, cash on delivery, or back to the cart. An action
/// the order cannot offer (no other method; cash on delivery is the method that
/// failed, or is not offered) is left out.
class PaymentFailedSheet extends StatelessWidget {
  const PaymentFailedSheet({
    super.key,
    required this.methodTitle,
    this.reason,
    this.canTryAnotherMethod = false,
    this.canPayCashOnDelivery = false,
  });

  /// The payment method that was refused.
  final String methodTitle;

  /// What the store said, shown under the text; none when it said nothing.
  final String? reason;
  final bool canTryAnotherMethod;
  final bool canPayCashOnDelivery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    // Figma: 34 px under the last button, the home-indicator area.
    final bottom = math.max(34.0, MediaQuery.paddingOf(context).bottom);
    final reasonText = reason?.trim() ?? '';
    void pop(PaymentFailedAction action) => Navigator.of(context).pop(action);
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The grab handle.
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 88,
                height: 88,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.dangerSurface,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  HubIcons.triangleAlert,
                  size: 40,
                  color: AppColors.danger,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.paymentFailedTitle,
              textAlign: TextAlign.center,
              style: t.heading1.copyWith(color: AppColors.inkHeading),
            ),
            const SizedBox(height: 14),
            Text(
              l10n.paymentFailedBody(methodTitle),
              textAlign: TextAlign.center,
              style: t.body.copyWith(color: AppColors.inkMuted),
            ),
            if (reasonText.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      HubIcons.info,
                      size: 18,
                      color: AppColors.inkSubtle,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.paymentFailedReason(reasonText),
                        style: t.caption.copyWith(color: AppColors.inkSubtle),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            // Figma: the buttons sit in a column 6 px under the rest, 10 apart.
            const SizedBox(height: 6),
            // The theme's buttons carry the 20 px lead icon the frame draws.
            if (canTryAnotherMethod) ...[
              FilledButton.icon(
                onPressed: () => pop(PaymentFailedAction.tryAnotherMethod),
                icon: const Icon(HubIcons.creditCard, size: 20),
                label: Text(l10n.paymentFailedTryAnother),
              ),
              const SizedBox(height: 10),
            ],
            if (canPayCashOnDelivery) ...[
              OutlinedButton.icon(
                onPressed: () => pop(PaymentFailedAction.payCashOnDelivery),
                icon: const Icon(HubIcons.banknote, size: 20),
                label: Text(l10n.paymentFailedPayCod),
              ),
              const SizedBox(height: 10),
            ],
            HubButton(
              label: l10n.paymentFailedBackToCart,
              style: HubButtonStyle.ghost,
              onPressed: () => pop(PaymentFailedAction.backToCart),
            ),
          ],
        ),
      ),
    );
  }
}
