import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Figma "radio": a 22 px circle on white — a 7 px navy ring (leaving an 8 px
/// white dot) once chosen, a 1.5 px `--hm-strong` ring before. Only the mark:
/// the row around it takes the tap.
class HubRadioDot extends StatelessWidget {
  const HubRadioDot({super.key, required this.selected, this.size = 22});

  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? AppColors.brandPrimary : AppColors.borderControl,
        width: selected ? 7 : 1.5,
      ),
    ),
  );
}
