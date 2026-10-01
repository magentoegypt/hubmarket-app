import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/theme_x.dart';
import 'grouped_list.dart';
import 'system_bar_clearance.dart';

/// Figma "footer": the bar pinned under a form or a list — white, a 1 px
/// `--hm-subtle` rule on top, 16 px at the sides, 12 px above its button and
/// 30 px below.
///
/// Pass it as a `Scaffold`'s `bottomNavigationBar:`. The 30 px under the button
/// is the frame's: an iPhone's 34 px home-indicator zone is 4 px taller, which
/// the thin indicator never reaches, so the system inset is only given way to
/// when it is larger than that; a phone with a persistent navigation bar (a
/// 3-button one is 47 dp) clears all of it (see [systemBarClearance]).
class HubBottomActionBar extends StatelessWidget {
  const HubBottomActionBar({
    super.key,
    required this.child,
    this.bottomSpace = defaultBottomSpace,
  });

  final Widget child;

  /// What the frame keeps under the button: 30 px on most, 28 on the address
  /// form.
  final double bottomSpace;

  static const double defaultBottomSpace = 30;

  @override
  Widget build(BuildContext context) {
    final clearance = systemBarClearance(context);
    return Material(
      color: groupCardColor(context),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          math.max(bottomSpace, clearance),
        ),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: context.isDarkMode
                  ? Colors.white12
                  : AppColors.borderSubtle,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
