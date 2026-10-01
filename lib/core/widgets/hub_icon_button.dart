import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Figma "icon-btn/…": a 40 px round tap target holding a 22 px outline icon, as
/// the app bars carry them (back, share, search, bell, cart). Transparent by
/// default; the product page puts them on a white disc over the photo
/// ([background]).
///
/// [showDot] draws the small orange "unread" dot at the top end (the bell).
class HubIconButton extends StatelessWidget {
  const HubIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.background,
    this.size = 40,
    this.iconSize = 22,
    this.showDot = false,
    this.dotBorderColor,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Also the accessible label.
  final String? tooltip;

  /// Icon colour; ink by default.
  final Color? color;

  /// Disc behind the icon; none by default.
  final Color? background;
  final double size;
  final double iconSize;
  final bool showDot;

  /// Rings the dot (the header's navy, so the dot reads on top of the bell).
  final Color? dotBorderColor;

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: background ?? Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              size: iconSize,
              color: color ?? AppColors.inkHeading,
            ),
          ),
        ),
      ),
    );
    if (showDot) {
      // Figma's dot is a 9 px orange circle at (23, 8) with its ring as an
      // outside stroke, so the ring grows the box instead of eating the core.
      final ring = dotBorderColor == null ? 0.0 : 1.5;
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          PositionedDirectional(
            top: 8 - ring,
            end: 8 - ring,
            child: IgnorePointer(
              child: Container(
                width: 9 + 2 * ring,
                height: 9 + 2 * ring,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: dotBorderColor == null
                      ? null
                      : Border.all(color: dotBorderColor!, width: ring),
                ),
              ),
            ),
          ),
        ],
      );
    }
    final label = tooltip;
    return label == null
        ? button
        : Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Tooltip(message: label, child: button),
          );
  }
}
