import 'package:flutter/material.dart';

import '../assets/app_images.dart';
import 'brand_lockup.dart';

/// The Hub Market logo lockup (H-and-cart mark + "Hub MARKET" wordmark) as
/// supplied by the client, rendered from `assets/branding/logo.png`.
///
/// The positive artwork is navy + orange for light surfaces; pass [onDark] for
/// navy headers, the splash and the footer — that switches to the reversed
/// artwork (white + orange) instead of tinting, so the orange cart stays
/// orange. Falls back to the text wordmark ([BrandLockup]) if the asset can't
/// load (e.g. widget tests).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 40, this.onDark = false});

  final double height;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      onDark ? AppImages.logoReversed : AppImages.logo,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => BrandLockup(
        color: onDark ? Colors.white : null,
        fontSize: height * 0.5,
      ),
    );
  }
}
