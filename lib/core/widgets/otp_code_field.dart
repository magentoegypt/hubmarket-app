import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/app_colors.dart';

/// The 6-digit OTP entry used by every WhatsApp-OTP flow (login, registration,
/// password reset, guest checkout). Renders a row of boxes driven by a
/// parent-owned [controller] so the host can read the code and `.clear()` it on
/// a wrong-code / resend.
///
/// A single focusable field sits transparently over the boxes — this keeps
/// paste, backspace and IME behaviour correct without juggling per-box focus.
/// The whole widget is forced **LTR** (via [Directionality]) so the boxes fill
/// left-to-right and digits read naturally even on the Arabic (RTL) screens
/// (Figma: "the 6-digit boxes stay LTR even in Arabic").
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.onCompleted,
  });

  final TextEditingController controller;
  final int length;
  final bool enabled;
  final bool autofocus;

  /// Fired once the full [length]-digit code has been entered.
  final ValueChanged<String>? onCompleted;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
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
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < widget.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _box(i, code)),
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
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(int i, String code) {
    final filled = i < code.length;
    final active = widget.enabled && i == code.length && _focus.hasFocus;
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: filled ? AppColors.surfaceTint : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? AppColors.brandPrimary
                : (filled ? AppColors.brandPrimary : AppColors.borderDefault),
            width: active ? 1.6 : 1,
          ),
        ),
        child: Center(
          child: Text(
            filled ? code[i] : '',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.inkHeading,
            ),
          ),
        ),
      ),
    );
  }
}
