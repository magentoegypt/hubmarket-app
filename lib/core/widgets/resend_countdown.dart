import 'dart:async';

import 'package:flutter/material.dart';

/// A "Resend code" action gated by the module's 60-second resend cooldown
/// (INTEGRATION.md §8). While counting down it is disabled and shows the
/// remaining seconds; when it reaches zero it re-enables. A code is sent the
/// moment the verify step appears, so it starts on cooldown by default.
class ResendCountdown extends StatefulWidget {
  const ResendCountdown({
    super.key,
    required this.onResend,
    required this.resendLabel,
    required this.countingLabel,
    this.cooldownSeconds = 60,
    this.startOnInit = true,
    this.style,
  });

  final VoidCallback onResend;

  /// Label for the enabled state, e.g. "Resend code".
  final String resendLabel;

  /// Builds the disabled/counting label, e.g. (s) => "Resend in ${s}s".
  final String Function(int secondsRemaining) countingLabel;

  final int cooldownSeconds;
  final bool startOnInit;
  final TextStyle? style;

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

  /// Restarts the cooldown from outside (e.g. the parent re-sent the code).
  void restart() => _start();

  void _onTap() {
    widget.onResend();
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final counting = _remaining > 0;
    return TextButton(
      onPressed: counting ? null : _onTap,
      child: Text(
        counting ? widget.countingLabel(_remaining) : widget.resendLabel,
        style: widget.style,
      ),
    );
  }
}
