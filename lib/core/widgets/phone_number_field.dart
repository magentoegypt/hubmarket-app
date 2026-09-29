import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The phone-entry field for the WhatsApp-OTP flows (Figma: a combined
/// `🇦🇪 +971 ⌄ | number` filled field). The country code is fixed to the UAE
/// (`+971`) — the store's allowed countries are UAE-only today (INTEGRATION.md
/// §10); the chevron is a cosmetic affordance for a future country picker.
///
/// The field **mirrors with the locale** to match Figma: the `+971` chip sits on
/// the leading edge — left in English (LTR), right in the Arabic (RTL) mirror —
/// while the dial code and the entered digits stay **Latin/LTR** internally
/// (numbers don't reverse), and the number sits adjacent to the chip in both.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.autofocus = false,
    this.validator,
    this.onSubmitted,
    this.dialCode = '+971',
    this.flag = '🇦🇪',
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool autofocus;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final String dialCode;
  final String flag;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // The InputDecorator places `prefixIcon` from the ambient direction, so the
    // chip mirrors to the leading edge (left LTR / right RTL) — matching Figma.
    // The digits are forced LTR so numbers never reverse, and `textAlign` is
    // pinned to the leading edge so the number sits right next to the chip in
    // both locales (not detached across the field).
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      textDirection: TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: _dialChip(),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }

  Widget _dialChip() => Padding(
    padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(flag, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 6),
        // Force the dial code LTR so it reads "+971", not "971+", in Arabic.
        Text(
          dialCode,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: AppColors.inkHeading,
          ),
        ),
        const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.inkFaint),
        const SizedBox(width: 8),
        Container(width: 1, height: 22, color: AppColors.borderDefault),
      ],
    ),
  );
}
