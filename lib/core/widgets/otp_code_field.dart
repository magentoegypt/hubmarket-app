import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';

/// The 6-digit code entry of Figma "05 Verify WhatsApp code", used wherever a
/// WhatsApp code is typed (the Verify screen, guest checkout). A row of 48×56
/// boxes: entered digits sit on a pale fill, the next box is outlined in navy
/// with an orange caret, the rest are empty outlines. [hasError] outlines them
/// all in red (a refused code). Driven by a parent-owned [controller] so the
/// host can read the code and `.clear()` it.
///
/// A single focusable field sits transparently over the boxes — this keeps
/// paste, backspace and IME behaviour correct without juggling per-box focus.
/// The row is forced **LTR** so the code reads left-to-right on the Arabic
/// screens too (Figma AR-05 "otp (LTR digits)").
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.hasError = false,
    this.onCompleted,
  });

  final TextEditingController controller;
  final int length;
  final bool enabled;
  final bool autofocus;
  final bool hasError;

  /// Fired once the full [length]-digit code has been entered.
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  static const double _boxWidth = 48;
  static const double _boxHeight = 56;
  static const double _gap = 10;

  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    // Rebuild on focus change too, so the active-box highlight appears/clears
    // immediately (not only when a digit is typed).
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onChanged() {
    setState(() {});
    if (widget.controller.text.length == widget.length) {
      widget.onCompleted?.call(widget.controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.controller.text;
    // Figma: the digits are Heading 2 (Bold 18).
    final digitStyle = AppTextStyles.of(context).heading2;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Full size on a phone; narrower screens shrink the boxes, never
          // the gaps.
          final fit =
              (constraints.maxWidth - _gap * (widget.length - 1)) /
              widget.length;
          final width = fit.clamp(24.0, _boxWidth).toDouble();
          final height = width * _boxHeight / _boxWidth;
          return Stack(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    SizedBox(
                      width: width,
                      height: height,
                      child: _box(i, code, digitStyle),
                    ),
                  ],
                ],
              ),
              // Transparent, full-width capture field over the boxes.
              Positioned.fill(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  showCursor: false,
                  enableInteractiveSelection: false,
                  style: const TextStyle(color: Colors.transparent, height: 0.01),
                  cursorColor: Colors.transparent,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(widget.length),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _box(int i, String code, TextStyle digitStyle) {
    final filled = i < code.length;
    final active = widget.enabled && i == code.length && _focus.hasFocus;
    final Color border;
    final double borderWidth;
    if (widget.hasError) {
      border = AppColors.danger;
      borderWidth = 1.5;
    } else if (active) {
      border = AppColors.brandPrimary;
      borderWidth = 2;
    } else {
      border = AppColors.borderStrong;
      borderWidth = 1;
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? AppColors.surfaceSubtle : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: borderWidth),
      ),
      child: Center(
        child: filled
            ? Text(
                code[i],
                style: digitStyle.copyWith(color: AppColors.inkHeading),
              )
            : active
            // The caret of the next digit (Figma: a 2×24 orange bar).
            ? Container(width: 2, height: 24, color: AppColors.accent)
            : null,
      ),
    );
  }
}
