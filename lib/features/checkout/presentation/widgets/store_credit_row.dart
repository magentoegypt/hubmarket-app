import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/failure_message.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../checkout_credit_controller.dart';
import 'checkout_parts.dart';

/// "Use my credit" on the payment step (Figma 18): the gift disc, what can be
/// used (or what this order uses), and the switch. Shown while the customer's
/// group may spend credit and there is some to use — see
/// [CheckoutCreditState.offered].
class CheckoutStoreCreditRow extends ConsumerWidget {
  const CheckoutStoreCreditRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = CheckoutText.of(context);
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
    String amount(Money money) => '\u2066${_exact(money)}\u2069';
    final subtitle = credit.isApplied
        ? l10n.checkoutCreditApplied(amount(credit.applied))
        : l10n.checkoutCreditAvailable(amount(credit.balance));
    return Semantics(
      toggled: credit.isApplied,
      child: Material(
        // No fill: the card is an outline on the page, as in the frame.
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
            // 14 / 12 inside the 1 px outline.
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
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
                    HubIcons.gift,
                    size: 18,
                    color: AppColors.successStrong,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.checkoutUseCredit, style: t.bodyStrong),
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
                  const SizedBox(
                    width: 44,
                    height: 26,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  )
                else
                  CheckoutSwitch(value: credit.isApplied),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "AED 120.00": a store-credit balance keeps its fils, as the frame writes it
/// (the other amounts drop the decimals of a whole figure).
String _exact(Money money) =>
    '${money.currency} ${NumberFormat('#,##0.00', 'en_US').format(money.amount)}';

/// The design's switch (Figma 18 "switch"): a 44 × 26 track with a 20 px white
/// knob, `--hm-strong` grey when off and navy when on. It only draws the state;
/// the row around it takes the tap.
class CheckoutSwitch extends StatelessWidget {
  const CheckoutSwitch({super.key, required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 44,
    height: 26,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: value ? AppColors.brandPrimary : AppColors.borderControl,
      borderRadius: BorderRadius.circular(13),
    ),
    // The knob sits at the start edge when off and the end edge when on, so
    // the switch mirrors in Arabic.
    alignment: value
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart,
    child: Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    ),
  );
}
