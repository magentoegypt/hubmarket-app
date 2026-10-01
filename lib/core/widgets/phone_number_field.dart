import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/hub_icons.dart';

/// The phone-entry field for the WhatsApp-OTP flows, as the frames draw their
/// mobile number (Figma "Input": a white 52 px field, the 20 px `phone` glyph,
/// then `+971 50 123 4567` in Body). The country code is fixed to the UAE
/// (`+971`) — the store's allowed countries are UAE-only today (INTEGRATION.md
/// §10) — so it is drawn as the start of the text and only the digits after it
/// are typed.
///
/// The glyph and the dial code sit on the leading edge — left in English (LTR),
/// right in Arabic (RTL) — while the dial code and the entered digits stay
/// **Latin/LTR** internally (numbers don't reverse), and the number sits next
/// to the dial code in both.
class PhoneNumberField extends StatelessWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    required this.hint,
    this.enabled = true,
    this.autofocus = false,
    this.validator,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.dialCode = '+971',
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final bool autofocus;
  final String? Function(String?)? validator;

  /// A refusal from the store to show under the field (e.g. the number is
  /// already in use), in place of the validator's message.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String dialCode;

  /// The frame's inset from the field's outer edge to its content: the 1 px
  /// outline plus 16 px of padding.
  static const double _inset = 17;

  /// Material 3's input decorator adds 4 px beside the text (after a prefix
  /// icon, and on an outlined field's open sides).
  static const double _decoratorGap = 4;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final body = t.body.copyWith(color: AppColors.inkHeading);
    // A 52 px field whatever the locale's line height (EN 20, AR 22).
    final vertical = (52 - body.fontSize! * body.height!) / 2;
    // The InputDecorator places `prefixIcon` from the ambient direction, so the
    // glyph and the dial code mirror to the leading edge (left LTR / right RTL).
    // The digits are forced LTR so numbers never reverse, and `textAlign` is
    // pinned to the leading edge so the number sits right next to the dial code
    // in both locales (not detached across the field).
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      textDirection: TextDirection.ltr,
      textAlign: rtl ? TextAlign.right : TextAlign.left,
      style: body,
      cursorColor: AppColors.brandPrimary,
      validator: validator,
      forceErrorText: errorText,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      errorBuilder: (context, error) => _FieldError(error),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: t.body.copyWith(color: AppColors.inkFaint),
        hintTextDirection: TextDirection.ltr,
        contentPadding: EdgeInsetsDirectional.fromSTEB(
          0,
          vertical,
          _inset - _decoratorGap,
          vertical,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: _inset),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(HubIcons.phone, size: 20, color: AppColors.inkMuted),
              const SizedBox(width: 10),
              // Force the dial code LTR so it reads "+971", not "971+", in
              // Arabic.
              Text(dialCode, textDirection: TextDirection.ltr, style: body),
            ],
          ),
        ),
        prefixIconConstraints: const BoxConstraints(),
      ),
    );
  }
}

/// The line under a field in error (Figma S6 "helper"): a 14 px alert and a red
/// Caption, 6 px under the field.
class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Padding(
      // The decorator keeps 4 px between the field and this line; the frame has 6.
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              HubIcons.triangleAlert,
              size: 14,
              color: AppColors.danger,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: t.caption.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
