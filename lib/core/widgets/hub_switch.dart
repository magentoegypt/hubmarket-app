import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Figma "switch": a 44 x 26 pill, navy with the white 20 px thumb at the end
/// when on, `border/control` grey with the thumb at the start when off. The thumb
/// sits at the trailing edge in both directions, so the switch mirrors in RTL
/// like the controls around it.
///
/// A null [onChanged] shows it disabled (half faded) and ignores taps.
class HubSwitch extends StatelessWidget {
  const HubSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  static const double width = 44;
  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: width,
            height: height,
            padding: const EdgeInsets.all(3),
            alignment: value
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              color: value ? AppColors.brandPrimary : AppColors.borderControl,
              borderRadius: BorderRadius.circular(height / 2),
            ),
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
