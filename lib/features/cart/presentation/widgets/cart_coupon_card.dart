import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';

/// The cart's coupon field, drawn as Figma 16's coupon (the frame's per-store
/// coupons need a backend the store doesn't have, so this one is for the whole
/// order): a caption label, a 44 px field with a tag glyph and the placeholder,
/// and a navy "Apply". Once a code is live a green line under it names the code,
/// the saving and a remove ×.
///
/// The copy button at the end of the field copies whatever code is in play —
/// what the shopper typed, or the live coupon — so a code seen in the
/// announcement bar or on an offer card can be carried out of the app.
class CartCouponCard extends StatelessWidget {
  const CartCouponCard({
    super.key,
    required this.controller,
    required this.appliedCoupon,
    required this.discount,
    required this.busy,
    required this.onApply,
    required this.onRemove,
  });

  final TextEditingController controller;
  final String? appliedCoupon;
  final Money? discount;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.cartCouponLabel,
              style: t.captionStrong.copyWith(color: AppColors.inkSubtle),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderStrong),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          HubIcons.tag,
                          size: 16,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            enabled: !busy,
                            style: t.body.copyWith(color: AppColors.inkHeading),
                            cursorColor: AppColors.brandPrimary,
                            decoration: InputDecoration(
                              hintText: l10n.cartCouponHint,
                              hintStyle: t.body.copyWith(
                                color: AppColors.inkMuted,
                              ),
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => busy ? null : onApply(),
                          ),
                        ),
                        _CopyCodeButton(
                          controller: controller,
                          appliedCoupon: appliedCoupon,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Figma: a 44 px navy button, "Apply" in Body Strong.
                Opacity(
                  opacity: busy ? 0.5 : 1,
                  child: Material(
                    color: AppColors.brandPrimary,
                    borderRadius: BorderRadius.circular(10),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: busy ? null : onApply,
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        child: Text(
                          l10n.cartApply,
                          style: t.bodyStrong.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (appliedCoupon != null) ...[
              const SizedBox(height: 10),
              _AppliedCoupon(
                code: appliedCoupon!,
                discount: discount,
                busy: busy,
                onRemove: onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "SAVE10 applied  −AED 20  ×" on a pale green band.
class _AppliedCoupon extends StatelessWidget {
  const _AppliedCoupon({
    required this.code,
    required this.discount,
    required this.busy,
    required this.onRemove,
  });

  final String code;
  final Money? discount;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = AppTextStyles.of(context);
    final ink = t.captionStrong.copyWith(color: AppColors.successStrong);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.successSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(HubIcons.tag, size: 16, color: AppColors.successStrong),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.cartCouponApplied(code), style: ink)),
          if (discount != null) ...[
            Text(
              '− ${discount!.formatted()}',
              textDirection: TextDirection.ltr,
              style: ink,
            ),
            const SizedBox(width: 10),
          ],
          InkWell(
            onTap: busy ? null : onRemove,
            borderRadius: BorderRadius.circular(12),
            child: const Icon(
              HubIcons.x,
              size: 16,
              color: AppColors.successStrong,
            ),
          ),
        ],
      ),
    );
  }
}

/// Copy-to-clipboard affordance at the trailing edge of the field (CL042-DEV13).
/// It listens to the field's own [TextEditingController] so it appears the
/// moment there is something to copy, and takes no space when there isn't.
class _CopyCodeButton extends StatelessWidget {
  const _CopyCodeButton({
    required this.controller,
    required this.appliedCoupon,
  });

  final TextEditingController controller;
  final String? appliedCoupon;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final code = value.text.trim().isNotEmpty
            ? value.text.trim()
            : (appliedCoupon ?? '');
        if (code.isEmpty) return const SizedBox.shrink();
        return InkWell(
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(ClipboardData(text: code));
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.cartCouponCopied)),
            );
          },
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            // Keeps a 44 px tap target without growing the field's height.
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 0, 4),
            child: Tooltip(
              message: l10n.actionCopy,
              child: const Icon(
                HubIcons.copy,
                size: 16,
                color: AppColors.brandPrimary,
              ),
            ),
          ),
        );
      },
    );
  }
}
