import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/offline_state.dart';
import '../../../../core/widgets/system_bar_clearance.dart';

/// Figma "Buy bar" (14, 14b): the sticky bottom bar of a product page — a white
/// bar with a `border/subtle` rule on top and a soft shadow above it, the
/// quantity pill ([QuantityPill]) and the 52 px navy button after it, 12 px
/// apart. The home-indicator zone under it is the device's own bottom inset
/// (the frame draws 30).
///
/// [note] sits above the row (a bundle bought on the website). The offline
/// banner docks right above the bar, where the tab bar would carry it.
class PdpBuyBar extends StatelessWidget {
  const PdpBuyBar({
    super.key,
    required this.quantity,
    required this.onQuantity,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.note,
  });

  final int quantity;
  final ValueChanged<int> onQuantity;

  /// "Add to cart · AED 50".
  final String label;

  /// Null shows the button disabled.
  final VoidCallback? onPressed;

  /// A spinner in place of the cart glyph while the cart works.
  final bool busy;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    // The frame leaves 30 px under the button — the home-indicator zone, 34 on
    // an iPhone — so this is the device's own bottom inset less those 4; a
    // persistent Android navigation bar is cleared as a whole.
    final bottom = math.max(systemBarClearance(context), 12.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OfflineBannerSlot(),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.borderSubtle)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A0F2145),
                blurRadius: 10,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(16, 12, 16, bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (note != null) note!,
                Row(
                  children: [
                    QuantityPill(
                      quantity: quantity,
                      onChanged: busy ? null : onQuantity,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: busy ? null : onPressed,
                        icon: busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(HubIcons.shoppingCart, size: 20),
                        // The price is part of the label: on a 360 dp phone
                        // "Add to cart · AED 28.50" shrinks a little instead of
                        // ending in "AED 28.…".
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(label, maxLines: 1),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Figma "Qty stepper": a 34 px pill with a 1 px `border/strong` outline, the
/// count in Body Strong between a 26 px muted "−" and a 26 px navy "+".
class QuantityPill extends StatelessWidget {
  const QuantityPill({super.key, required this.quantity, required this.onChanged});

  final int quantity;

  /// Null disables both buttons.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    Widget round(
      IconData icon, {
      required Color fill,
      required Color ink,
      VoidCallback? onTap,
    }) => Material(
      color: fill,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 16, color: ink),
        ),
      ),
    );

    final change = onChanged;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderStrong),
      ),
      // "−  1  +" reads the same in Arabic: the Arabic frame keeps the order.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            round(
              HubIcons.minus,
              fill: AppColors.surfaceSubtle,
              ink: AppColors.inkHeading,
              onTap: change != null && quantity > 1
                  ? () => change(quantity - 1)
                  : null,
            ),
            const SizedBox(width: 6),
            Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
            ),
            const SizedBox(width: 6),
            round(
              HubIcons.plus,
              fill: AppColors.brandPrimary,
              ink: Colors.white,
              onTap: change == null ? null : () => change(quantity + 1),
            ),
          ],
        ),
      ),
    );
  }
}
