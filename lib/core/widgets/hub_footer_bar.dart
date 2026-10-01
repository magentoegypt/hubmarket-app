import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_x.dart';

/// Figma "footer": the white bar a form page pins under its content (20c Save
/// changes, 20h Save): a 1 px `border/subtle` rule on top, the 52 px button
/// ([child]) with 16 px at the sides and 12 above and below. (The frame's 28 px
/// underneath is the home-indicator zone; the app's tab bar sits there.)
class HubFooterBar extends StatelessWidget {
  const HubFooterBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.isDarkMode ? AppColors.surfaceDark : Colors.white,
      border: Border(
        top: BorderSide(
          color: context.isDarkMode ? Colors.white12 : AppColors.borderSubtle,
        ),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: child,
    ),
  );
}
