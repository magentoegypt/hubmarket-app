import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../app/theme/hub_icons.dart';
import '../../../../l10n/l10n.dart';
import '../../../account/domain/customer_address.dart';
import '../../../cart/domain/cart.dart';
import '../../../catalog/domain/money.dart';
import '../../domain/checkout.dart';
import '../checkout_credit_controller.dart';

/// Shared building blocks of the three checkout steps (Figma 17 / 18 / 18b):
/// white cards on the muted page, the design's type scale, the step indicator,
/// the pinned footer and the totals card.

/// The Figma `--hm-subtle` fill (`#FAFBFD`) behind a selected shipping method
/// and a saved card: a hair off white.
const Color checkoutSelectedFill = Color(0xFFFAFBFD);

/// The checkout's type: the Figma text styles ([AppTextStyles], so Arabic
/// switches to Tajawal by itself) in the fixed inks. Every checkout surface is a
/// light card, in dark mode too, so the inks are the tokens, not theme colours.
///
///     final t = CheckoutText.of(context);
///     Text(title, style: t.title)
class CheckoutText {
  CheckoutText._(this._t);

  factory CheckoutText.of(BuildContext context) =>
      CheckoutText._(AppTextStyles.of(context));

  final AppTextStyles _t;

  /// Heading 1 — Playfair Display 22 (the review page's title).
  TextStyle get heading1 => _t.heading1.copyWith(color: AppColors.inkHeading);

  /// Heading 2 — DM Sans Bold 18 ("Payment method").
  TextStyle get heading2 => _t.heading2.copyWith(color: AppColors.inkHeading);

  /// Title — card titles, 16 semi-bold.
  TextStyle get title => _t.title.copyWith(color: AppColors.inkHeading);

  /// Body in ink.
  TextStyle get body => _t.body.copyWith(color: AppColors.inkHeading);

  /// Body in `--hm-subtle`: the label of an amount row.
  TextStyle get bodySubtle => _t.body.copyWith(color: AppColors.inkSubtle);

  /// Body in muted grey: an address line.
  TextStyle get bodyMuted => _t.body.copyWith(color: AppColors.inkMuted);

  /// Body Strong — names, amounts in a row.
  TextStyle get bodyStrong =>
      _t.bodyStrong.copyWith(color: AppColors.inkHeading);

  /// Caption in muted grey.
  TextStyle get caption => _t.caption.copyWith(color: AppColors.inkMuted);

  /// Caption in `--hm-subtle`.
  TextStyle get captionSubtle =>
      _t.caption.copyWith(color: AppColors.inkSubtle);

  /// Caption Strong — field labels.
  TextStyle get captionStrong =>
      _t.captionStrong.copyWith(color: AppColors.inkHeading);

  /// Micro — the address label chip, card brand chips.
  TextStyle get micro => _t.micro.copyWith(color: AppColors.inkSubtle);

  /// Price — 15 bold.
  TextStyle get price => _t.price.copyWith(color: AppColors.inkHeading);

  /// Orange text links: "Change", "Forgot your password?".
  TextStyle get link => _t.bodyStrong.copyWith(color: AppColors.accentStrong);

  /// The small orange link ("Edit").
  TextStyle get linkSmall =>
      _t.captionStrong.copyWith(color: AppColors.accentStrong);
}

/// The comma that joins an address on one line: ", ", or the Arabic "، ".
String addressSeparator(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar' ? '، ' : ', ';

/// A saved address on one line, in the order the frames print it (see
/// [shipToAddressLine]) and with the country: "Apt 1204, Marina Gate 2, Dubai
/// Marina, Dubai, UAE".
String savedAddressLine(BuildContext context, CustomerAddress a) =>
    shipToAddressLine(
      apartment: a.apartment,
      street: a.street,
      area: a.city,
      emirate: a.region.isNotEmpty ? a.region : a.city,
      country: AppLocalizations.of(context).checkoutAddressCountry,
      separator: addressSeparator(context),
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

/// A white, rounded checkout card (Figma: padding 14, radius 16) with an
/// optional title row.
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
    final t = CheckoutText.of(context);
    final rows = <Widget>[
      if (title != null || trailing != null)
        Row(
          children: [
            Expanded(
              child: title == null
                  ? const SizedBox.shrink()
                  : Text(title!, style: t.title),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ...children,
    ];
    // A Material, so the ripple of a link or an option inside shows on the
    // white (it would paint under a plain coloured box).
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) SizedBox(height: spacing),
                rows[i],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The design's 22 px radio: a thick navy ring (7 px, a white dot left in the
/// middle) when selected, a thin `--hm-strong` one otherwise.
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
        color: selected ? AppColors.brandPrimary : AppColors.borderControl,
        width: selected ? 7 : 1.5,
      ),
    ),
  );
}

/// A tappable option card (address, shipping method, payment method): a navy
/// 1.5 px outline when selected, a hairline otherwise. [padding] is the
/// design's, measured inside the outline.
class CheckoutOption extends StatelessWidget {
  const CheckoutOption({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = 12,
    this.selectedFill = checkoutSelectedFill,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  /// Background once selected — a faint tint for shipping methods (Figma 17),
  /// white for payment methods (18).
  final Color selectedFill;

  @override
  Widget build(BuildContext context) {
    final border = selected ? 1.5 : 1.0;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(
        color: selected ? AppColors.brandPrimary : AppColors.borderSubtle,
        width: border,
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
          child: Padding(
            padding: padding + EdgeInsets.all(border),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// An orange text action at the end of a card's title row: "Change", "Edit".
/// With an [icon] it is the small variant (14 px glyph, 12 px label).
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
    final t = CheckoutText.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        // The row keeps the card's own 22 px height and the text its place at
        // the card's edge; the start side widens the tap target.
        padding: const EdgeInsetsDirectional.only(start: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppColors.accentStrong),
              const SizedBox(width: 4),
            ],
            Text(label, style: icon == null ? t.link : t.linkSmall),
          ],
        ),
      ),
    );
  }
}

/// A money amount, always laid out left to right ("AED 553") so the code
/// stays in front of the figure in Arabic too.
class MoneyText extends StatelessWidget {
  const MoneyText(this.money, {super.key, this.style});

  final Money? money;

  /// Body Strong when null.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    money?.formatted() ?? '—',
    textDirection: TextDirection.ltr,
    style: style ?? CheckoutText.of(context).bodyStrong,
  );
}

/// Shipping → Payment → Review, under the app bar (Figma "stepper": white, a
/// hairline under it, 24 px circles joined by 28 px rules, spread across the
/// width). A completed step is a green tick and can be tapped to go back to it;
/// the current one is navy; the ones to come are outlined.
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
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
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
    final t = CheckoutText.of(context);
    final Widget badge;
    if (done) {
      badge = const _Circle(
        color: AppColors.successStrong,
        child: Icon(HubIcons.check, size: 14, color: Colors.white),
      );
    } else {
      badge = _Circle(
        color: active ? AppColors.brandPrimary : Colors.white,
        border: active ? null : AppColors.borderStrong,
        child: Text(
          '$number',
          style: t.captionStrong.copyWith(
            color: active ? Colors.white : AppColors.inkMuted,
          ),
        ),
      );
    }
    // Active: Body Strong in ink; completed: Body in ink; to come: Body muted.
    final style = active
        ? t.bodyStrong
        : (done ? t.body : t.body.copyWith(color: AppColors.inkMuted));
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
            Text(label, maxLines: 1, style: style),
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
    color: done ? AppColors.successStrong : AppColors.borderStrong,
  );
}

/// The white bar pinned under each step (Figma "footer": a hairline on top, 12
/// above the content and 30 below it): the step's primary action, with a line
/// above it. The bottom is the home-indicator area — the device's own inset when
/// it is larger than the design's 30.
class CheckoutFooter extends StatelessWidget {
  const CheckoutFooter({super.key, required this.children, this.spacing = 8});

  final List<Widget> children;

  /// Gap between the children: 8 under a total row, 10 under a note.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    // With the keyboard up there is no home indicator to clear: the footer
    // gives the room back to the form.
    final bottom = MediaQuery.viewInsetsOf(context).bottom > 0
        ? 12.0
        : math.max(30.0, MediaQuery.paddingOf(context).bottom);
    // A Container, so the hairline on top adds its own pixel to the height.
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// The green shield line above a footer button: "Payments are encrypted by our
/// payment partner" (18), "Your payment information is encrypted and secure"
/// (18b).
class CheckoutSecureNote extends StatelessWidget {
  const CheckoutSecureNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Icon(
        HubIcons.shieldCheck,
        size: 14,
        color: AppColors.successStrong,
      ),
      const SizedBox(width: 6),
      Flexible(child: Text(text, style: CheckoutText.of(context).caption)),
    ],
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

  /// Already formatted ("AED 10", "FREE", "− AED 5").
  final String value;
  final Color? valueColor;

  /// The total line: a Title label and the Price style.
  final bool emphasis;

  /// Overrides the value's style — the footer's "Total incl. shipping".
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final t = CheckoutText.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: emphasis ? t.title : t.bodySubtle)),
        const SizedBox(width: 12),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: (valueStyle ?? (emphasis ? t.price : t.bodyStrong)).copyWith(
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Subtotal, shipping, any discount, store credit used and the total — "Order
/// summary" on the payment step (a 10 px rhythm, the item and package count
/// beside the title), "Order total" on the review step (12 px).
class CheckoutTotalsCard extends ConsumerWidget {
  const CheckoutTotalsCard({
    super.key,
    required this.title,
    required this.cart,
    this.trailing,
    this.spacing = 12,
    this.shipping,
    this.grandTotal,
  });

  final String title;
  final Cart cart;

  /// Next to the title — the item count on the payment step.
  final String? trailing;

  /// The gap between the rows: 10 on the payment step, 12 on the review step.
  final double spacing;
  final ShippingMethodOption? shipping;

  /// What Magento charges — the controller's total, read after the shipping and
  /// payment methods are on the quote. Falls back to the cart's.
  final Money? grandTotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = CheckoutText.of(context);
    final totals = cart.totals;
    final discount = totals.discount;
    final shippingAmount = shipping?.amount;
    // Cart.hm_store_credit, re-read whenever credit is used or given back.
    final credit = ref.watch(checkoutCreditProvider.select((s) => s.applied));
    return CheckoutCard(
      title: title,
      spacing: spacing,
      trailing: trailing == null ? null : Text(trailing!, style: t.caption),
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
            value: '− ${discount.formatted()}',
            valueColor: AppColors.successStrong,
          ),
        if (credit != null)
          CheckoutAmountRow(
            label: l10n.checkoutStoreCredit,
            value: '− ${credit.formatted()}',
            valueColor: AppColors.successStrong,
          ),
        const Divider(height: 1, thickness: 1, color: AppColors.borderSubtle),
        CheckoutAmountRow(
          label: l10n.checkoutTotalInclVat,
          value: (grandTotal ?? totals.grandTotal)?.formatted() ?? '—',
          emphasis: true,
        ),
      ],
    );
  }
}
