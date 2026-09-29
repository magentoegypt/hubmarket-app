import 'package:flutter/material.dart';

import '../assets/app_images.dart';
import 'brand_lockup.dart';

/// The Hub Market brand lockup rendered as the real logo image — the ornate Z-mark
/// over the `HUB MARKET` wordmark (`assets/branding/logo.png`) — matching the Figma
/// header / drawer / footer lockup.
///
/// The asset is a burgundy silhouette on transparent, so pass [onDark] to tint
/// it white for dark surfaces (footer, burgundy headers). Falls back to the
/// text wordmark ([BrandLockup]) if the asset can't load (e.g. widget tests).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 40, this.onDark = false});

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final tint = onDark ? Colors.white : null;
    return Image.asset(
      AppImages.logo,
      height: height,
      fit: BoxFit.contain,
      color: tint,
      colorBlendMode: tint != null ? BlendMode.srcIn : null,
      errorBuilder: (_, __, ___) =>
          BrandLockup(color: tint, fontSize: height * 0.5),
    );
  }
}
