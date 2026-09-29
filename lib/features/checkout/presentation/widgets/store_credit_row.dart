import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../l10n/l10n.dart';
import '../checkout_credit_controller.dart';

/// "Use my credit" on the payment step (Figma 18): the gift disc, what can be
/// used (or what this order uses), and the switch. Shown while the customer's
/// group may spend credit and there is some to use — see
/// [CheckoutCreditState.offered].
class CheckoutStoreCreditRow extends ConsumerWidget {
  const CheckoutStoreCreditRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final state = ref.watch(checkoutCreditProvider);
    ref.listen<Object?>(checkoutCreditProvider.select((s) => s.error), (
      previous,
      next,
    ) {
      if (next != null && !identical(previous, next)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(serverMessageOr(context, next, l10n.errorGeneric)),
          ),
        );
      }
    });
    final credit = state.credit;
    if (credit == null || !credit.offered) return const SizedBox.shrink();
    // "AED 120.00" keeps its order inside an Arabic sentence.
    String amount(String text) => '\u2066$text\u2069';
    final subtitle = credit.isApplied
        ? l10n.checkoutCreditApplied(amount(credit.applied.formatted()))
        : l10n.checkoutCreditAvailable(amount(credit.balance.formatted()));
    return Semantics(
      toggled: credit.isApplied,
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: state.busy
              ? null
              : () => ref
                    .read(checkoutCreditProvider.notifier)
                    .setUse(!credit.isApplied),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.successSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.card_giftcard_outlined,
                    size: 18,
                    color: AppColors.successStrong,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.checkoutUseCredit,
                        style: t.bodyStrong.copyWith(
                          color: AppColors.inkHeading,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: t.caption.copyWith(
                          color: AppColors.successStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (state.busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                else
                  Switch(
                    value: credit.isApplied,
                    onChanged: (use) =>
                        ref.read(checkoutCreditProvider.notifier).setUse(use),
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.brandPrimary,
                    inactiveThumbColor: Colors.white,
                    inactiveTrackColor: AppColors.borderControl,
                    trackOutlineColor: const WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
