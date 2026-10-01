import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_text_styles.dart';
import 'auth_widgets.dart';
import '../../../../app/theme/hub_icons.dart';

/// Auth-screen heading (Figma 03 / 05 / 06): the Display title — Playfair
/// Display in English, Tajawal ExtraBold in Arabic — over a muted Body line,
/// both at the start edge. [trailing] sits under the subtitle (05's "Change
/// number" link).
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.gap = 6,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  /// Space between the lines — 6 on Sign in, 8 on the screens with a badge.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final t = AppTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: t.display.copyWith(color: AppColors.inkHeading)),
        if (subtitle != null) ...[
          SizedBox(height: gap),
          Text(subtitle!, style: t.body.copyWith(color: AppColors.inkMuted)),
        ],
        if (trailing != null) ...[
          SizedBox(height: gap),
          Align(alignment: AlignmentDirectional.centerStart, child: trailing),
        ],
      ],
    );
  }
}

/// The rounded-square icon badge above a heading (05: green chat bubble, 06:
/// orange lock).
class AuthBadge extends StatelessWidget {
  const AuthBadge({
    super.key,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  /// 05 Verify WhatsApp code.
  const AuthBadge.whatsapp({super.key})
    : icon = const MessageCircleIcon(),
      background = AppColors.successSubtle,
      foreground = AppColors.successStrong;

  /// 06 Reset password.
  const AuthBadge.lock({super.key})
    : icon = const Icon(HubIcons.lock),
      background = AppColors.accentSubtle,
      foreground = AppColors.accentStrong;

  final Widget icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: IconTheme(
          data: IconThemeData(size: 30, color: foreground),
          child: Center(child: icon),
        ),
      ),
    );
  }
}
