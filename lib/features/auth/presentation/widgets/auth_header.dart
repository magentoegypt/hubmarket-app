import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';

/// Auth-screen header per Figma: a blush circular badge with a burgundy icon,
/// a bold heading, and a muted subtitle. (The brand logo lockup sits in the app
/// bar above this — see the auth screens.)
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        CircleAvatar(
          radius: 42,
          backgroundColor: AppColors.surfaceTint,
          child: Icon(icon, color: AppColors.brandPrimary, size: 34),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.inkHeading,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
