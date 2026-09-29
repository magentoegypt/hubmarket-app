import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../l10n/l10n.dart';
import '../../../cart/domain/cart.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/checkout.dart';

/// Shared building blocks of the three checkout steps (Figma 17 / 18 / 18b):
/// white cards on the muted page, the design's type scale, the step indicator,
/// the pinned footer and the totals card.

/// The checkout type scale (Figma "EN/…" text styles). Colours are the fixed
/// tokens: every checkout surface is a light card, in dark mode too.
abstract final class CheckoutText {
  static const TextStyle title = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.inkHeading,
  );
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.inkHeading,
  );
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.inkHeading,
  );
  static const TextStyle bodyMuted = TextStyle(
    fontSize: 14,
    color: AppColors.inkMuted,
  );
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.inkMuted,
  );
  static const TextStyle captionStrong = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.inkHeading,
  );
  static const TextStyle price = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w700,
    color: AppColors.inkHeading,
  );

  /// Orange text links: "Change", "Edit", "Forgot your password?".
  static const TextStyle link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.accentStrong,
  );
}

/// The footer buttons' label (Figma "EN/Button"). Derived from the theme's
/// label style: a bare TextStyle would replace it and lose the locale's font.
ButtonStyle checkoutButtonStyle(BuildContext context) =>
    FilledButton.styleFrom(textStyle: checkoutButtonText(context));

TextStyle? checkoutButtonText(BuildContext context, {double fontSize = 15}) =>
    Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
    );

/// A phone number for display: `+971501234567` → `+971 50 123 4567`, in a
/// left-to-right isolate so it keeps its order inside an Arabic line.
String displayPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
  final uae = RegExp(r'^\+971(\d{2})(\d{3})(\d{4})$').firstMatch(digits);
  final text = uae == null
      ? raw
      : '+971 ${uae.group(1)} ${uae.group(2)} ${uae.group(3)}';
  return '\u2066$text\u2069';
}

/// A white, rounded checkout card with an optional title row.
class CheckoutCard extends StatelessWidget {
  const CheckoutCard({
    super.key,
    this.title,
    this.trailing,
    this.spacing = 12,
    required this.children,
  });

  final String? title;

  /// Sits at the end of the title row — "Edit", an item count.
  final Widget? trailing;

  /// Gap between the title row and each child.
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (title != null || trailing != null)
        Row(
          children: [
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : Text(title!, style: CheckoutText.title),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ...children,
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// The design's 22px radio: a thick navy ring when selected, a thin grey one
/// otherwise.
class CheckoutRadio extends StatelessWidget {
  const CheckoutRadio({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 150),
    width: 22,
    height: 22,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? AppColors.brandPrimary : AppColors.inkFaint,
        width: selected ? 7 : 1.5,
      ),
    ),
  );
}

/// A tappable option card (address, shipping method, payment method): navy
/// outline when selected, a hairline otherwise.
class CheckoutOption extends StatelessWidget {
  const CheckoutOption({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.selectedFill = AppColors.surfaceSubtle,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// Background once selected — a faint tint for shipping methods (Figma 17),
  /// white for payment methods (18).
  final Color selectedFill;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: selected ? AppColors.brandPrimary : AppColors.borderDefault,
        width: selected ? 1.5 : 1,
      ),
    );
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      child: Material(
        color: selected ? selectedFill : Colors.white,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// An orange text action at the end of a card's title row: "Change", "Edit".
class CheckoutLink extends StatelessWidget {
  const CheckoutLink({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final small = icon != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.accentStrong),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: small
                  ? CheckoutText.link.copyWith(fontSize: 12)
                  : CheckoutText.link,
            ),
          ],
        ),
      ),
    );
  }
}

/// A money amount, always laid out left to right ("AED 553.00") so the code
/// stays in front of the figure in Arabic too.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.money, {
    super.key,
    this.style = CheckoutText.bodyStrong,
  });

  final Money? money;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Text(
    money?.formatted() ?? '—',
    textDirection: TextDirection.ltr,
    style: style,
  );
}

/// Shipping → Payment → Review, under the app bar. Completed steps turn green
/// and can be tapped to go back to them.
class CheckoutStepIndicator extends StatelessWidget {
  const CheckoutStepIndicator({
    super.key,
    required this.current,
    required this.onTap,
  });

  final CheckoutStep current;

  /// A completed step was tapped.
  final ValueChanged<CheckoutStep> onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(CheckoutStep step) => switch (step) {
      CheckoutStep.shipping => l10n.checkoutStepShipping,
      CheckoutStep.payment => l10n.checkoutStepPayment,
      CheckoutStep.review => l10n.checkoutStepReview,
    };
    final children = <Widget>[];
    for (final step in CheckoutStep.values) {
      if (step.index > 0) {
        children.add(_Connector(done: step.index <= current.index));
      }
      children.add(
        _StepItem(
          number: step.index + 1,
          label: label(step),
          done: step.index < current.index,
          active: step == current,
          onTap: step.index < current.index ? () => onTap(step) : null,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.borderDefault)),
      ),
      // Spread across the width like the design; on a screen too narrow for
      // the three labels (or a large text scale) the row scales down instead
      // of overflowing.
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
    this.onTap,
  });

  final int number;
  final String label;
  final bool done;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget badge;
    if (done) {
      badge = const _Circle(
        color: AppColors.successStrong,
        child: Icon(Icons.check, size: 14, color: Colors.white),
      );
    } else {
      badge = _Circle(
        color: active ? AppColors.brandPrimary : Colors.white,
        border: active ? null : AppColors.borderStrong,
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.inkMuted,
          ),
        ),
      );
    }
    return Semantics(
      button: onTap != null,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            badge,
            const SizedBox(width: 6),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active || done
                    ? AppColors.inkHeading
                    : AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.color, required this.child, this.border});

  final Color color;
  final Color? border;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: border == null ? null : Border.all(color: border!),
    ),
    child: child,
  );
}

class _Connector extends StatelessWidget {
  const _Connector({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) => Container(
    width: 28,
    height: 1,
    margin: const EdgeInsets.symmetric(horizontal: 6),
    color: done ? AppColors.successStrong : AppColors.borderStrong,
  );
}

/// The white bar pinned under each step: the step's primary action, with an
/// optional line above it.
class CheckoutFooter extends StatelessWidget {
  const CheckoutFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: AppColors.borderDefault)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              children[i],
            ],
          ],
        ),
      ),
    ),
  );
}

/// A label / amount line in the totals cards and the footer.
class CheckoutAmountRow extends StatelessWidget {
  const CheckoutAmountRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.emphasis = false,
    this.valueStyle,
  });

  final String label;

  /// Already formatted ("AED 10.00", "FREE", "−AED 5.00").
  final String value;
  final Color? valueColor;

  /// The total line: a stronger label and the price style.
  final bool emphasis;

  /// Overrides the value's style — the footer's "Total incl. shipping".
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: emphasis ? CheckoutText.title : CheckoutText.bodyMuted,
        ),
      ),
      const SizedBox(width: 12),
      Text(
        value,
        textDirection: TextDirection.ltr,
        style:
            (valueStyle ??
                    (emphasis ? CheckoutText.price : CheckoutText.bodyStrong))
                .copyWith(color: valueColor),
      ),
    ],
  );
}

/// Subtotal, shipping, any discount and the total — "Order summary" on the
/// payment step, "Order total" on the review step.
class CheckoutTotalsCard extends StatelessWidget {
  const CheckoutTotalsCard({
    super.key,
    required this.title,
    required this.cart,
    this.trailing,
    this.shipping,
    this.grandTotal,
  });

  final String title;
  final Cart cart;

  /// Next to the title — the item count on the payment step.
  final String? trailing;
  final ShippingMethodOption? shipping;

  /// What Magento charges — the controller's total, read after the shipping and
  /// payment methods are on the quote. Falls back to the cart's.
  final Money? grandTotal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final totals = cart.totals;
    final discount = totals.discount;
    final shippingAmount = shipping?.amount;
    return CheckoutCard(
      title: title,
      spacing: 10,
      trailing: trailing == null
          ? null
          : Text(trailing!, style: CheckoutText.caption),
      children: [
        CheckoutAmountRow(
          label: l10n.cartSubtotal,
          value: totals.subtotal?.formatted() ?? '—',
        ),
        if (shipping != null)
          CheckoutAmountRow(
            label: l10n.checkoutShippingFee,
            value: shipping!.isFree
                ? l10n.cartDeliveryFree
                : shippingAmount!.formatted(),
            valueColor: shipping!.isFree ? AppColors.successStrong : null,
          ),
        if (discount != null)
          CheckoutAmountRow(
            label: totals.appliedCoupon != null
                ? l10n.cartPromoCode(totals.appliedCoupon!)
                : l10n.cartDiscount,
            value: '−${discount.formatted()}',
            valueColor: AppColors.successStrong,
          ),
        const Divider(height: 1, thickness: 1, color: AppColors.borderDefault),
        CheckoutAmountRow(
          label: l10n.checkoutTotalInclVat,
          value: (grandTotal ?? totals.grandTotal)?.formatted() ?? '—',
          emphasis: true,
        ),
      ],
    );
  }
}
