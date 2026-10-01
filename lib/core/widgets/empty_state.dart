import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_text_styles.dart';
import '../../app/theme/theme_x.dart';

/// The state page the Figma "S" frames share (S1 empty cart, S3 offline, S7
/// page not found): a 112 px tinted disc with a 48 px icon, the title (Heading
/// 1), a muted body line and — 8 px further down — the actions, full width, 10
/// apart. Centred in the space it is given, with 32 px at the sides.
///
/// The disc's tone follows the state: the default is S1's (orange tint, orange
/// icon); [discColor] and [iconColor] give S2 (`surfaceSubtle`, `inkMuted`), S3
/// (`warningSubtle`, `warning`) and the others.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.secondaryAction,
    this.discColor = AppColors.accentSubtle,
    this.iconColor = AppColors.accentStrong,
    this.titleStyle,
    this.gap = 14,
  });

  final IconData icon;
  final String title;
  final String? body;

  /// The main action (a filled button); it stretches to the full width.
  final Widget? action;

  /// A second action under [action], 10 px lower (an outlined or ghost button).
  final Widget? secondaryAction;

  final Color discColor;
  final Color iconColor;

  /// Heading 1 unless a frame says otherwise (S7 uses Heading 2).
  final TextStyle? titleStyle;

  /// Between the disc, the title and the body: 14 in S1 / S3, 12 in S7.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(color: discColor, shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: iconColor),
            ),
            SizedBox(height: gap),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (titleStyle ?? t.heading1).copyWith(
                color: context.scaffoldHeading,
              ),
            ),
            if (body != null) ...[
              SizedBox(height: gap),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: t.body.copyWith(color: context.scaffoldMuted),
              ),
            ],
            if (action != null || secondaryAction != null) ...[
              SizedBox(height: gap + 8),
              if (action != null)
                SizedBox(width: double.infinity, child: action),
              if (action != null && secondaryAction != null)
                const SizedBox(height: 10),
              if (secondaryAction != null)
                SizedBox(width: double.infinity, child: secondaryAction),
            ],
          ],
        ),
      ),
    );
  }
}
