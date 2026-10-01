import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import '../../../../l10n/l10n.dart';
import '../../../../app/theme/hub_icons.dart';

/// Figma "Input" (03 / 04 / 06; states Default · Focused · Error in S6): a
/// label over a white 52-px field with a leading icon, and under it the helper
/// line — the error when there is one, otherwise an optional [helper]. Without
/// a [label] it is just the field (the [hint] then says what goes in it).
///
/// Errors come from two places and render the same way: the [validator]
/// (checked by the enclosing [Form]) and [errorText], a refusal the screen got
/// back from the store. [showErrorBorder] — or a validator returning `''` —
/// outlines the field in red without a line of its own, for when a banner or
/// the [helper] already says what is wrong.
class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    this.label,
    this.icon,
    this.hint,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.obscureText = false,
    this.ltrInput = false,
    this.trailing,
    this.validator,
    this.errorText,
    this.showErrorBorder = false,
    this.helper,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final IconData? icon;
  final String? hint;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final bool obscureText;

  /// Keeps what is typed left-to-right (e-mail, phone) in Arabic too, while
  /// the text still sits at the field's leading edge.
  final bool ltrInput;

  /// Trailing control inside the field — the password visibility toggle.
  final Widget? trailing;
  final String? Function(String value)? validator;
  final String? errorText;
  final bool showErrorBorder;

  /// Shown under the field when it has no error (e.g. the password rule).
  final Widget? helper;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // A 52-px field whatever the locale's line height (EN 20, AR 22).
    final lineHeight = t.body.fontSize! * t.body.height!;
    final vertical = (52 - lineHeight) / 2;
    return FormField<String>(
      initialValue: widget.controller.text,
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(widget.controller.text),
      builder: (field) {
        final error = field.errorText ?? widget.errorText;
        final red = error != null || widget.showErrorBorder;
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
            TextField(
              controller: widget.controller,
              focusNode: _focus,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              autofillHints: widget.autofillHints,
              obscureText: widget.obscureText,
              textDirection: widget.ltrInput ? TextDirection.ltr : null,
              textAlign: widget.ltrInput && rtl ? TextAlign.right : TextAlign.start,
              style: t.body.copyWith(color: AppColors.inkHeading),
              cursorColor: AppColors.brandPrimary,
              onChanged: (value) {
                field.didChange(value);
                widget.onChanged?.call(value);
              },
              onSubmitted: widget.onSubmitted,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                hintText: widget.hint,
                hintStyle: t.body.copyWith(color: AppColors.inkFaint),
                hintTextDirection: widget.ltrInput ? TextDirection.ltr : null,
                contentPadding: EdgeInsetsDirectional.fromSTEB(
                  widget.icon == null ? 16 : 0,
                  vertical,
                  widget.trailing == null ? 16 : 0,
                  vertical,
                ),
                prefixIcon: widget.icon == null
                    ? null
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(
                          start: 16,
                          end: 10,
                        ),
                        child: Icon(
                          widget.icon,
                          size: 20,
                          color: AppColors.inkMuted,
                        ),
                      ),
                prefixIconConstraints: const BoxConstraints(),
                suffixIcon: widget.trailing == null
                    ? null
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(end: 6),
                        child: widget.trailing,
                      ),
                suffixIconConstraints: const BoxConstraints(),
                border: _outline(AppColors.borderStrong, 1),
                enabledBorder: red
                    ? _outline(AppColors.danger, 1.5)
                    : _outline(AppColors.borderStrong, 1),
                focusedBorder: red
                    ? _outline(AppColors.danger, 1.5)
                    : _outline(AppColors.brandPrimary, 1.5),
              ),
            ),
            // An empty error marks the field without a line of its own — the
            // [helper] under it (a rule) says what is missing.
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 6),
              AuthHelperLine.error(error),
            ] else if (widget.helper != null) ...[
              const SizedBox(height: 6),
              widget.helper!,
            ],
          ],
        );
      },
    );
  }

  static OutlineInputBorder _outline(Color color, double width) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// The small line under a field (Figma S6 "helper"): an icon and a caption —
/// red with an alert for an error, green with a tick for a satisfied rule,
/// muted for a rule not met yet.
class AuthHelperLine extends StatelessWidget {
  const AuthHelperLine({
    super.key,
    required this.text,
    required this.icon,
    required this.color,
    this.centered = false,
  });

  const AuthHelperLine.error(this.text, {super.key, this.centered = false})
    : icon = HubIcons.triangleAlert,
      color = AppColors.danger;

  /// A rule under a field — green once [met], red when the form was sent
  /// without it ([failed]), muted until then.
  const AuthHelperLine.rule(
    this.text, {
    super.key,
    required bool met,
    bool failed = false,
  }) : icon = failed && !met ? HubIcons.triangleAlert : HubIcons.check,
       color = met
           ? AppColors.successStrong
           : (failed ? AppColors.danger : AppColors.inkMuted),
       centered = false;

  final String text;
  final IconData icon;
  final Color color;

  /// Centred under a centred control (the code boxes) instead of start-aligned.
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    final label = Text(
      text,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: t.caption.copyWith(color: color),
    );
    return Row(
      mainAxisAlignment: centered
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 6),
        if (centered) Flexible(child: label) else Expanded(child: label),
      ],
    );
  }
}

/// The eye toggle inside a password field (shows / hides the characters).
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
  });

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: obscured ? l10n.authShowPassword : l10n.authHidePassword,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        obscured ? HubIcons.eye : HubIcons.eyeOff,
        size: 20,
        color: AppColors.inkMuted,
      ),
    );
  }
}
