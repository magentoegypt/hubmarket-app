import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/hub_icons.dart';
import '../../l10n/l10n.dart';
import '../phone/phone_country.dart';
import '../phone/phone_field_controller.dart';
import '../validation/phone.dart';
import 'country_picker_sheet.dart';

/// The phone-entry field of the app, as the website's phone fields are: a
/// country chip (the flag and the calling code, `+971`, with a chevron) that
/// opens the list of countries, and the number as it is written in that
/// country. Any country can be picked, and the number is checked against that
/// country's own rules.
///
/// Drawn as the frames draw their mobile number (Figma "Input": a white 52 px
/// field, 12 pt corners) with the chip where the phone glyph was. The chip and
/// the digits sit on the leading edge — left in English, right in Arabic —
/// while the calling code and the digits stay Latin/LTR internally (numbers do
/// not reverse), and the number sits next to the chip in both.
///
/// A number can also be pasted or filled in with its country code
/// (`+971 50 123 4567`, `00971…`): the country follows the code and the rest is
/// what stays in the field ([PhoneFieldController]).
class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.enabled = true,
    this.autofocus = false,
    this.mobileOnly = false,
    this.errorText,
    this.helper,
    this.autofillHints,
    this.textInputAction = TextInputAction.done,
    this.onChanged,
    this.onSubmitted,
  });

  final PhoneFieldController controller;

  /// A caption over the field (Figma "Input" label), when the screen has no
  /// label of its own.
  final String? label;

  /// What the empty field says; the country's own example number by default.
  final String? hint;
  final bool enabled;
  final bool autofocus;

  /// The number must be a mobile (a WhatsApp or SMS code does not reach a
  /// landline): sign-in, registration, password reset, changing the mobile.
  /// An address takes any valid number.
  final bool mobileOnly;

  /// A refusal from the store to show under the field (e.g. the number is
  /// already in use), in place of the validator's message.
  final String? errorText;

  /// Shown under the field when it has no error.
  final Widget? helper;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;

  /// The text of the field changed (what the shopper typed, or the country was
  /// picked: [PhoneFieldController.text] and its country are current).
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// The frame's inset from the field's outer edge to its content: the 1 px
  /// outline plus 16 px of padding.
  static const double inset = 17;

  /// Material 3's input decorator adds 4 px beside the text (after a prefix
  /// icon, and on an outlined field's open sides).
  static const double _decoratorGap = 4;

  /// The longest text a field takes: a number of 15 digits with its spaces.
  static const int maxLength = 24;

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String? _validate(BuildContext context) {
    final controller = widget.controller;
    final l10n = AppLocalizations.of(context);
    if (controller.isEmpty) return l10n.validationRequired;
    if (controller.isValid(mobileOnly: widget.mobileOnly)) return null;
    final country = controller.country.name(
      Localizations.localeOf(context).languageCode,
    );
    return widget.mobileOnly
        ? l10n.validationMobileInvalid(country)
        : l10n.validationPhoneInvalid(country);
  }

  Future<void> _pickCountry() async {
    final picked = await showCountryPicker(
      context,
      selected: widget.controller.country,
    );
    if (picked == null || !mounted) return;
    widget.controller.country = picked;
    _focus.requestFocus();
    widget.onChanged?.call(widget.controller.text.text);
  }

  static OutlineInputBorder _outline(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final l10n = AppLocalizations.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final body = t.body.copyWith(color: AppColors.inkHeading);
    // A 52 px field whatever the locale's line height (EN 20, AR 22).
    final vertical = (52 - body.fontSize! * body.height!) / 2;
    // Like [AuthField], a [FormField] around a plain text field: the message
    // under it is the validator's, or the store's own refusal ([errorText]),
    // and a new refusal replaces the last at once.
    return FormField<String>(
      initialValue: widget.controller.text.text,
      validator: (_) => _validate(context),
      builder: (field) {
        final error = field.errorText ?? widget.errorText;
        final red = error != null;
        final field0 = ListenableBuilder(
          listenable: widget.controller,
          builder: (context, _) {
            final country = widget.controller.country;
            final language = Localizations.localeOf(context).languageCode;
            // The InputDecorator places `prefixIcon` from the ambient direction,
            // so the chip mirrors to the leading edge (left LTR / right RTL).
            // The digits are forced LTR so numbers never reverse, and `textAlign`
            // is pinned to the leading edge so the number sits right next to the
            // chip in both locales (not detached across the field).
            return TextField(
              controller: widget.controller.text,
              focusNode: _focus,
              enabled: widget.enabled,
              autofocus: widget.autofocus,
              keyboardType: TextInputType.phone,
              textInputAction: widget.textInputAction,
              autofillHints: widget.autofillHints,
              inputFormatters: [
                const _PhoneTextFormatter(),
                LengthLimitingTextInputFormatter(PhoneNumberField.maxLength),
              ],
              textDirection: TextDirection.ltr,
              textAlign: rtl ? TextAlign.right : TextAlign.left,
              style: body,
              cursorColor: AppColors.brandPrimary,
              onChanged: (value) {
                field.didChange(value);
                widget.onChanged?.call(value);
              },
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: widget.enabled
                    ? Colors.white
                    : AppColors.surfaceSubtle,
                hintText: widget.hint ?? country.exampleNumber,
                hintStyle: t.body.copyWith(color: AppColors.inkFaint),
                hintTextDirection: TextDirection.ltr,
                contentPadding: EdgeInsetsDirectional.fromSTEB(
                  0,
                  vertical,
                  PhoneNumberField.inset - PhoneNumberField._decoratorGap,
                  vertical,
                ),
                prefixIcon: _CountryChip(
                  country: country,
                  semanticLabel: l10n.phoneCountryChoose(
                    country.name(language),
                    country.dial,
                  ),
                  onTap: widget.enabled ? _pickCountry : null,
                ),
                prefixIconConstraints: const BoxConstraints(),
                border: _outline(AppColors.borderStrong, 1),
                enabledBorder: red
                    ? _outline(AppColors.danger, 1.5)
                    : _outline(AppColors.borderStrong, 1),
                focusedBorder: red
                    ? _outline(AppColors.danger, 1.5)
                    : _outline(AppColors.brandPrimary, 1.5),
                disabledBorder: _outline(AppColors.borderSubtle, 1),
              ),
            );
          },
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.label != null) ...[
              Text(
                widget.label!,
                style: t.captionStrong.copyWith(color: AppColors.inkHeading),
              ),
              const SizedBox(height: 6),
            ],
            field0,
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 6),
              _FieldError(error),
            ] else if (widget.helper != null) ...[
              const SizedBox(height: 6),
              widget.helper!,
            ],
          ],
        );
      },
    );
  }
}

/// The chip at the start of the field: the country's flag and calling code and a
/// chevron, over a hairline that parts it from the number. Tapping it opens the
/// list of countries.
class _CountryChip extends StatelessWidget {
  const _CountryChip({
    required this.country,
    required this.semanticLabel,
    required this.onTap,
  });

  final PhoneCountry country;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final muted = onTap == null;
    return Semantics(
      button: true,
      enabled: !muted,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('phone-country-chip'),
        onTap: onTap,
        // The field's rounded corner on the chip's side, whichever side it is.
        borderRadius: const BorderRadiusDirectional.horizontal(
          start: Radius.circular(12),
        ).resolve(Directionality.of(context)),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: PhoneNumberField.inset,
            end: 10,
            top: 11,
            bottom: 11,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: muted ? 0.5 : 1,
                child: Text(
                  country.flag,
                  style: const TextStyle(fontSize: 22, height: 1),
                ),
              ),
              const SizedBox(width: 8),
              // Latin and left to right in Arabic too: "+971", not "971+".
              Text(
                country.dial,
                textDirection: TextDirection.ltr,
                style: t.body.copyWith(
                  color: muted ? AppColors.inkMuted : AppColors.inkHeading,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                HubIcons.chevronDown,
                size: 16,
                color: AppColors.inkMuted,
              ),
              const SizedBox(width: 10),
              const SizedBox(
                width: 1,
                height: 24,
                child: ColoredBox(color: AppColors.borderSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps a phone field to what a number is made of: digits (an Arabic keyboard's
/// are written as 0-9), spaces, and `+ - ( ) .`.
class _PhoneTextFormatter extends TextInputFormatter {
  const _PhoneTextFormatter();

  static final RegExp _notPhone = RegExp(r'[^0-9+\-().\s]');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = Phone.latinDigits(newValue.text).replaceAll(_notPhone, '');
    if (cleaned == newValue.text) return newValue;
    final removed = newValue.text.length - cleaned.length;
    final offset = (newValue.selection.baseOffset - removed).clamp(
      0,
      cleaned.length,
    );
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: offset),
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
    return Row(
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
    );
  }
}
