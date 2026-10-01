import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../core/widgets/network_image.dart';
import '../../../../l10n/l10n.dart';
import '../../domain/cart.dart';

/// One cart line (Figma 16 "cart-item"): the photo, the name, the chosen
/// options, the price with its old price beside it, and under them the quantity
/// stepper and "Remove".
///
/// In selection mode ([selecting], Figma "Select") a checkbox leads the line
/// and tapping the line ticks it; the stepper and Remove stay where they are.
class CartItemTile extends StatelessWidget {
  const CartItemTile({
    super.key,
    required this.item,
    required this.busy,
    required this.onChangeQuantity,
    required this.onRemove,
    this.selecting = false,
    this.selected = false,
    this.onToggleSelected,
  });

  final CartItem item;

  /// A cart change is in flight: the stepper and Remove wait for it.
  final bool busy;
  final ValueChanged<int> onChangeQuantity;
  final VoidCallback onRemove;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggleSelected;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final unit = item.unitPrice;
    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selecting) ...[
          Padding(
            padding: const EdgeInsets.only(top: 31),
            child: _Checkbox(selected: selected),
          ),
          const SizedBox(width: 12),
        ],
        HubImage(
          url: item.imageUrl,
          width: 84,
          height: 84,
          borderRadius: BorderRadius.circular(12),
          placeholder: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
          error: (_) => const ColoredBox(color: AppColors.surfaceSubtle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
              ),
              if (item.options.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  item.options.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: AppColors.inkMuted),
                ),
              ],
              if (unit != null) ...[
                const SizedBox(height: 4),
                // Orange while the line is discounted, ink otherwise; the old
                // price follows in caption type.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      unit.formatted(),
                      textDirection: TextDirection.ltr,
                      style: t.price.copyWith(
                        color: item.isDiscounted
                            ? AppColors.accentStrong
                            : AppColors.inkHeading,
                      ),
                    ),
                    if (item.isDiscounted) ...[
                      const SizedBox(width: 6),
                      Text(
                        item.originalUnitPrice!.formatted(),
                        textDirection: TextDirection.ltr,
                        // The storefront (and QA) want exactly one line through
                        // the price before the discount.
                        style: t.caption.copyWith(
                          color: AppColors.inkMuted,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CartQuantityStepper(
                    quantity: item.quantity,
                    onChanged: busy ? null : onChangeQuantity,
                  ),
                  _RemoveLink(onTap: busy ? null : onRemove),
                ],
              ),
            ],
          ),
        ),
      ],
    );
    if (!selecting) return line;
    return InkWell(
      onTap: onToggleSelected,
      borderRadius: BorderRadius.circular(12),
      child: Semantics(selected: selected, child: line),
    );
  }
}

/// The 22 px tick box of selection mode: a navy tick once chosen, an outline
/// before.
class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => Icon(
    selected ? HubIcons.squareCheck : HubIcons.square,
    size: 22,
    color: selected ? AppColors.brandPrimary : AppColors.borderControl,
  );
}

/// Figma "Qty stepper": a 34 px pill with a hairline outline, a grey minus, the
/// count and a navy plus, 26 px discs 6 px from the count.
class CartQuantityStepper extends StatelessWidget {
  const CartQuantityStepper({
    super.key,
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;

  /// Null while a change is in flight.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    // The Arabic frame keeps the stepper as it is in English — minus first,
    // plus last — so it does not mirror with the page.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Disc(
              icon: HubIcons.minus,
              label: AppLocalizations.of(context).cartQuantityDecrease,
              fill: AppColors.surfaceSubtle,
              ink: AppColors.inkHeading,
              onTap: onChanged == null ? null : () => onChanged!(quantity - 1),
            ),
            const SizedBox(width: 6),
            Text(
              '$quantity',
              style: t.bodyStrong.copyWith(color: AppColors.inkHeading),
            ),
            const SizedBox(width: 6),
            _Disc(
              icon: HubIcons.plus,
              label: AppLocalizations.of(context).cartQuantityIncrease,
              fill: AppColors.brandPrimary,
              ink: Colors.white,
              onTap: onChanged == null ? null : () => onChanged!(quantity + 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const _Disc({
    required this.icon,
    required this.label,
    required this.fill,
    required this.ink,
    required this.onTap,
  });

  final IconData icon;

  /// What a screen reader says for the button.
  final String label;
  final Color fill;
  final Color ink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: Material(
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
    ),
  );
}

/// "Remove" with its trash glyph, in muted caption type.
class _RemoveLink extends StatelessWidget {
  const _RemoveLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        // The stepper's height, for a tap target as tall as the row.
        height: 34,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(HubIcons.trash2, size: 16, color: AppColors.inkMuted),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context).cartRemove,
              style: t.caption.copyWith(color: AppColors.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
