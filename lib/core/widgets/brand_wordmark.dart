import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// The `Hub Market` text wordmark used in the marketing footer — a 1:1 match for the
/// storefront's footer brand rule:
///
/// ```css
/// .beauty-footer__brand { font-family: ui-sans-serif, system-ui, sans-serif;
///                         font-size: 24px; font-weight: 700;
///                         letter-spacing: .02em; color: #fff }
/// ```
///
/// The name is Magento's site title read at *default* scope, so it is the same
/// Latin string in every store view — hence a literal here rather than an ARB
/// string, and a forced LTR direction inside the RTL footer.
///
/// The font family is pinned for the same reason `BrandLockup` pins Playfair:
/// the base theme font switches to Cairo in Arabic ([AppTheme.fontFor]), which
/// would otherwise render the brand name in the Arabic face.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({
    super.key,
    this.color = Colors.white,
    this.fontSize = 24,
  });

  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Hub Market',
      textDirection: TextDirection.ltr,
      style: TextStyle(
        fontFamily: AppTheme.latinFont,
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
        // The web's .02em, kept proportional if the size is ever overridden.
        letterSpacing: fontSize * 0.02,
        color: color,
      ),
    );
  }
}
