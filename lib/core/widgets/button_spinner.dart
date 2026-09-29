import 'package:flutter/material.dart';

/// The small in-button progress indicator used inside a busy [FilledButton]
/// across the OTP/auth/checkout flows. Extracted so the busy-state look stays
/// consistent in one place.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
