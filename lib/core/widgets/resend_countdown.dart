import 'dart:async';

import 'package:flutter/material.dart';

/// A "Resend code" action gated by the WhatsApp code's 60-second resend
/// cooldown. While counting down it is disabled and shows the remaining time;
/// at zero it re-enables. A code is sent the moment the verify step appears,
/// so it starts on cooldown by default.
///
/// The counting state is [countingLabel] as a disabled text button, unless
/// [countingBuilder] draws it (the Verify screen's "🕑 Resend code in 00:42").
class ResendCountdown extends StatefulWidget {
  const ResendCountdown({
    super.key,
    required this.onResend,
    required this.resendLabel,
    required this.countingLabel,
    this.countingBuilder,
    this.cooldownSeconds = 60,
    this.startOnInit = true,
    this.style,
  });

  final VoidCallback onResend;

  /// Label for the enabled state, e.g. "Resend code".
  final String resendLabel;

  /// Builds the disabled/counting label, e.g. (s) => "Resend in ${s}s".
  final String Function(int secondsRemaining) countingLabel;

  /// Replaces the counting state's text button when set.
  final Widget Function(BuildContext context, int secondsRemaining)?
  countingBuilder;

  final int cooldownSeconds;
  final bool startOnInit;
  final TextStyle? style;

  /// `m:ss` → `00:42`, the Verify screen's countdown format.
  static String clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  State<ResendCountdown> createState() => _ResendCountdownState();
}

class _ResendCountdownState extends State<ResendCountdown> {
  Timer? _timer;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    if (widget.startOnInit) _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start() {
    _timer?.cancel();
    setState(() => _remaining = widget.cooldownSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) t.cancel();
    });
  }

  void _onTap() {
    widget.onResend();
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final counting = _remaining > 0;
    if (counting && widget.countingBuilder != null) {
      return widget.countingBuilder!(context, _remaining);
    }
    return TextButton(
      onPressed: counting ? null : _onTap,
      child: Text(
        counting ? widget.countingLabel(_remaining) : widget.resendLabel,
        style: widget.style,
      ),
    );
  }
}
