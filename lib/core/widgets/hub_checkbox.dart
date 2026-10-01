import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/hub_icons.dart';

/// Figma "checkbox": 22 px, radius 6; ticked it is navy with a white 14 px
/// check, unticked white with a 1.5 px `border/control` outline.
///
/// Only the box: the row around it (a label, a description) owns the tap target,
/// so a null [onChanged] draws it disabled and a row tap can still toggle it.
class HubCheckbox extends StatelessWidget {
  const HubCheckbox({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      checked: value,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? AppColors.brandPrimary : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: value
                  ? null
                  : Border.all(color: AppColors.borderControl, width: 1.5),
            ),
            child: value
                ? const Icon(HubIcons.check, size: 14, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
