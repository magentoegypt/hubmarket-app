import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/theme_x.dart';
import '../../../../core/hubapp/hubapp.dart';
import '../../../../l10n/l10n.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/return_draft.dart';
import '../../domain/returns.dart';
import 'return_widgets.dart';

/// The building blocks of the return form (Figma 23).

/// "Returns go to the store that sold the item (…)" (Figma 65:2812).
class ReturnStoreNote extends StatelessWidget {
  const ReturnStoreNote({super.key, required this.seller});

  final String? seller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = seller?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.storefront_outlined,
            size: 18,
            color: returnsSubtleText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name.isEmpty
                  ? l10n.returnsStoreNote
                  : l10n.returnsStoreNoteSeller(name),
              style: const TextStyle(
                fontSize: 12,
                height: 16 / 12,
                color: returnsSubtleText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A field that opens a picker (Figma input with a trailing chevron).
class ReturnPickerField extends StatelessWidget {
  const ReturnPickerField({
    super.key,
    required this.icon,
    required this.text,
    required this.placeholder,
    required this.onTap,
  });

  final IconData icon;
  final String? text;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = text?.trim() ?? '';
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.inkHeading),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value.isEmpty ? placeholder : value,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    color: value.isEmpty
                        ? AppColors.inkMuted
                        : AppColors.inkHeading,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 20,
                color: AppColors.inkMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Sold by …" above a seller's lines when the order has several sellers.
class ReturnSellerHeader extends StatelessWidget {
  const ReturnSellerHeader({super.key, required this.seller});

  final HmSellerSummary? seller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = seller?.name.trim() ?? '';
    if (name.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 10),
      child: Row(
        children: [
          const Icon(
            Icons.storefront_outlined,
            size: 14,
            color: returnsVendorColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.returnsSoldBy(name),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: returnsVendorColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One order line (Figma 65:2786): tick box, thumbnail, name, options and
/// paid price, and the quantity to return — a stepper when the customer may
/// return part of it.
class ReturnLineTile extends StatelessWidget {
  const ReturnLineTile({
    super.key,
    required this.item,
    required this.availability,
    required this.quantity,
    required this.minQuantity,
    required this.blockingSeller,
    required this.unit,
    required this.onToggle,
    required this.onQuantity,
  });

  final ReturnableItem item;
  final LineAvailability availability;

  /// Units ticked, null when not ticked.
  final int? quantity;
  final int minQuantity;

  /// The seller of the ticked lines, which blocks this one's seller.
  final String? blockingSeller;
  final Money? unit;
  final VoidCallback onToggle;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final selected = availability == LineAvailability.selected;
    final enabled = selected || availability == LineAvailability.available;
    final caption = [
      for (final o in item.options)
        if (o.value.isNotEmpty) o.value,
      if (unit != null) unit!.formatted(),
    ].join(' · ');
    final String? why = switch (availability) {
      LineAvailability.unavailable =>
        item.openReturnNumbers.isNotEmpty
            ? l10n.returnsItemInReturn(
                item.openReturnNumbers.map(returnNumberLabel).join(', '),
              )
            : l10n.returnsItemNotReturnable,
      LineAvailability.otherSeller =>
        (item.seller?.name.trim() ?? '').isNotEmpty
            ? l10n.returnsOtherSellerNote(item.seller!.name.trim())
            : l10n.returnsOtherSellerGeneric,
      _ => null,
    };
    final stepper =
        selected && item.qtyReturnable > minQuantity && quantity != null;
    return Semantics(
      checked: selected,
      enabled: enabled,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? AppColors.brandPrimary : AppColors.borderSubtle,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onToggle : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Opacity(
              opacity: enabled ? 1 : 0.55,
              child: Row(
                children: [
                  _TickBox(selected: selected, enabled: enabled),
                  const SizedBox(width: 12),
                  ReturnThumb(url: item.imageUrl, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 20 / 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkHeading,
                          ),
                        ),
                        if (caption.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 16 / 12,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                        if (why != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              why,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 16 / 12,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (stepper)
                    _Stepper(
                      value: quantity!,
                      min: minQuantity,
                      max: item.qtyReturnable,
                      onChanged: onQuantity,
                    )
                  else if (enabled)
                    Text(
                      '×${quantity ?? item.qtyReturnable}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 20 / 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkHeading,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tick box (Figma 65:2780): navy with a white tick when ticked.
class _TickBox extends StatelessWidget {
  const _TickBox({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: selected
          ? AppColors.brandPrimary
          : (enabled ? Colors.white : AppColors.surfaceMuted),
      borderRadius: BorderRadius.circular(6),
      border: selected
          ? null
          : Border.all(
              color: enabled ? AppColors.borderControl : AppColors.borderStrong,
              width: 1.5,
            ),
    ),
    child: selected
        ? const Icon(Icons.check, size: 14, color: Colors.white)
        : null,
  );
}

/// − n + for a line's quantity.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    Widget button(IconData icon, VoidCallback? onTap) => SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onTap,
        padding: EdgeInsets.zero,
        iconSize: 16,
        tooltip: l10n.returnsQuantity,
        style: IconButton.styleFrom(
          side: const BorderSide(color: AppColors.borderStrong),
          foregroundColor: AppColors.brandPrimary,
          disabledForegroundColor: AppColors.borderStrong,
        ),
        icon: Icon(icon),
      ),
    );
    return Semantics(
      label: l10n.returnsQuantity,
      value: '$value',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Icons.remove, value > min ? () => onChanged(value - 1) : null),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.inkHeading,
              ),
            ),
          ),
          button(Icons.add, value < max ? () => onChanged(value + 1) : null),
        ],
      ),
    );
  }
}

/// Pill chips, one selected (Figma chips: navy when selected).
class ReturnChoiceChips<T> extends StatelessWidget {
  const ReturnChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final value in values)
        Semantics(
          selected: value == selected,
          button: true,
          child: Material(
            color: value == selected ? AppColors.brandPrimary : Colors.white,
            shape: StadiumBorder(
              side: value == selected
                  ? BorderSide.none
                  : const BorderSide(color: AppColors.borderStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onSelected(value),
              child: Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                // Hug the label (an aligned Container would fill the row).
                child: Center(
                  widthFactor: 1,
                  child: Text(
                    label(value),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: value == selected
                          ? Colors.white
                          : AppColors.inkHeading,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// A radio choice as a bordered row (Figma 65:2795).
class ReturnRadioRow extends StatelessWidget {
  const ReturnRadioRow({
    super.key,
    required this.selected,
    required this.label,
    required this.onTap,
    this.trailing,
  });

  final bool selected;
  final String label;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    inMutuallyExclusiveGroup: true,
    checked: selected,
    child: Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? AppColors.brandPrimary : AppColors.borderSubtle,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.brandPrimary
                        : AppColors.borderControl,
                    width: selected ? 7 : 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    color: selected ? AppColors.inkHeading : AppColors.inkMuted,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                Text(
                  trailing!,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkHeading,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// The Submit bar (Figma 65:2875).
class ReturnSubmitBar extends StatelessWidget {
  const ReturnSubmitBar({
    super.key,
    required this.submitting,
    required this.onSubmit,
  });

  final bool submitting;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: context.hairline)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: FilledButton(
        onPressed: submitting ? null : onSubmit,
        child: submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            // Styled on the Text so it keeps the theme's font (a button's
            // textStyle replaces it).
            : Text(
                l10n.returnsSubmit,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class ReturnSheetTitle extends StatelessWidget {
  const ReturnSheetTitle(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.inkHeading,
      ),
    ),
  );
}

class ReturnSheetOption extends StatelessWidget {
  const ReturnSheetOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.caption,
  });

  final String label;
  final String? caption;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    selected: selected,
    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    title: Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        color: AppColors.inkHeading,
      ),
    ),
    subtitle: caption == null
        ? null
        : Text(
            caption!,
            style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
    trailing: selected
        ? const Icon(Icons.check, color: AppColors.brandPrimary, size: 20)
        : null,
  );
}
