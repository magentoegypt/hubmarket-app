import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';

/// The `HUB MARKET` wordmark in Playfair Display — the brand lockup used in app bars
/// and the drawer header. Stays English/Latin in both languages (per design).
///
/// (The favicon Z-mark is `.ico`, which Flutter can't render as an image asset;
/// a PNG/SVG mark can be slotted in front of the wordmark when available.)
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.color, this.fontSize = 22});

  final Color? color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'HUB MARKET',
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontFamily: AppTheme.displayFont,
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
        letterSpacing: 2,
        color: color ?? AppColors.brandPrimary,
      ),
    );
  }
}
