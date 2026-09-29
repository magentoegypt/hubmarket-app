import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Shared back button matching the Figma chevron — a thin `‹` in ink, not the
/// stock Material arrow. Uses `arrow_back_ios_new`, whose `IconData` sets
/// `matchTextDirection: true`, so it auto-mirrors to `›` in Arabic/RTL. Never
/// wrap it in a manual `Transform`/direction flip — that double-mirrors it (see
/// the rtl-arrow-double-flip lesson).
class HubBackButton extends StatelessWidget {
  const HubBackButton({super.key, this.color, this.onPressed});

  /// Icon colour. Defaults to [AppColors.inkHeading]; pass white for navy
  /// surfaces.
  final Color? color;

  /// Overrides the default `Navigator.maybePop` behaviour when set.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
      color: color ?? AppColors.inkHeading,
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onPressed ?? () => Navigator.maybePop(context),
    );
  }
}
