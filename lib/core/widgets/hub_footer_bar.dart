import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_x.dart';
import 'system_bar_clearance.dart';

/// Figma "footer": the white bar a form page pins under its content (20c Save
/// changes, 20h Save): a 1 px `border/subtle` rule on top, the 52 px button
/// ([child]) with 16 px at the sides and 12 above. The frame leaves 28 px under
/// it, an iPhone's home-indicator zone; a phone's persistent navigation bar is
/// cleared as a whole ([systemBarClearance]). It sits at the very bottom, under
/// no tab bar (a page that shows one must not use it: the tab bar clears the
/// system bar already).
class HubFooterBar extends StatelessWidget {
  const HubFooterBar({super.key, required this.child});

  final Widget child;

  /// What the frame keeps under the button.
  static const double _frameSpace = 28;

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
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        math.max(_frameSpace, systemBarClearance(context)),
      ),
      child: child,
    ),
  );
}
