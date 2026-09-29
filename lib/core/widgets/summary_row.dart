import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// A single label/value line in an order summary — shared by the Cart and
/// Checkout summaries so both read identically. The value is forced LTR so AED
/// amounts (and the leading "−" on a discount) render correctly in Arabic/RTL.
class SummaryRow extends StatelessWidget {
  const SummaryRow({
    super.key,
    required this.label,
    this.value,
    this.valueColor,
    this.valueWeight = FontWeight.w500,
  });

  final String label;
  final String? value;
  final Color? valueColor;
  final FontWeight valueWeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.inkMuted),
          ),
        ),
        Text(
          value ?? '—',
          textDirection: TextDirection.ltr,
          style: TextStyle(
            fontSize: 13,
            fontWeight: valueWeight,
            color: valueColor ?? AppColors.inkHeading,
          ),
        ),
      ],
    );
  }
}
