import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// The text styles of Figma "01 · Cover & Foundations" — `EN/*` and `AR/*` —
/// picked for the ambient locale. English sets DM Sans (Playfair Display for
/// Display / Heading 1); Arabic sets Tajawal, whose styles run a line taller
/// and a step heavier where the Latin face would use SemiBold.
///
/// Line heights are Figma's, with the extra leading split evenly above and
/// below the glyphs as Figma does. Colours are left to the caller:
///
///     final t = AppTextStyles.of(context);
///     Text(title, style: t.display.copyWith(color: AppColors.inkHeading));
@immutable
class AppTextStyles {
  const AppTextStyles._(this.arabic);

  factory AppTextStyles.of(BuildContext context) =>
      AppTextStyles._(Localizations.localeOf(context).languageCode == 'ar');

  /// Whether the Arabic (`AR/*`) variants are in use.
  final bool arabic;

  /// EN/Display — Playfair Display Bold 28/34 · AR/Display — Tajawal ExtraBold 28/38.
  TextStyle get display => arabic
      ? _ar(28, 38, FontWeight.w800)
      : _en(28, 34, FontWeight.w700, family: AppTheme.displayFont);

  /// EN/Heading 1 — Playfair Display Bold 22/28 · AR — Tajawal Bold 22/30.
  TextStyle get heading1 => arabic
      ? _ar(22, 30, FontWeight.w700)
      : _en(22, 28, FontWeight.w700, family: AppTheme.displayFont);

  /// EN/Heading 2 — DM Sans Bold 18/24 · AR — Tajawal Bold 18/26.
  TextStyle get heading2 =>
      arabic ? _ar(18, 26, FontWeight.w700) : _en(18, 24, FontWeight.w700);

  /// EN/Title — DM Sans SemiBold 16/22 · AR — Tajawal Bold 16/24.
  TextStyle get title =>
      arabic ? _ar(16, 24, FontWeight.w700) : _en(16, 22, FontWeight.w600);

  /// EN/Body — DM Sans Regular 14/20 · AR — Tajawal Regular 14/22.
  TextStyle get body =>
      arabic ? _ar(14, 22, FontWeight.w400) : _en(14, 20, FontWeight.w400);

  /// EN/Body Strong — DM Sans SemiBold 14/20 · AR — Tajawal Medium 14/22.
  TextStyle get bodyStrong =>
      arabic ? _ar(14, 22, FontWeight.w500) : _en(14, 20, FontWeight.w600);

  /// EN/Caption — DM Sans Regular 12/16 · AR — Tajawal Regular 12/18.
  TextStyle get caption =>
      arabic ? _ar(12, 18, FontWeight.w400) : _en(12, 16, FontWeight.w400);

  /// EN/Caption Strong — DM Sans SemiBold 12/16 · AR — Tajawal Medium 12/18.
  TextStyle get captionStrong =>
      arabic ? _ar(12, 18, FontWeight.w500) : _en(12, 16, FontWeight.w600);

  /// EN/Micro — DM Sans Bold 11/14 · AR — Tajawal Bold 11/16.
  TextStyle get micro =>
      arabic ? _ar(11, 16, FontWeight.w700) : _en(11, 14, FontWeight.w700);

  /// EN/Button — DM Sans Bold 15/20 · AR — Tajawal Bold 15/22.
  TextStyle get button =>
      arabic ? _ar(15, 22, FontWeight.w700) : _en(15, 20, FontWeight.w700);

  /// EN/Price — DM Sans Bold 15/20 · AR — Tajawal Bold 15/22.
  TextStyle get price =>
      arabic ? _ar(15, 22, FontWeight.w700) : _en(15, 20, FontWeight.w700);

  /// EN/Price Large — DM Sans Bold 24/30 · AR — Tajawal Bold 24/32 (the product
  /// page's price).
  TextStyle get priceLarge =>
      arabic ? _ar(24, 32, FontWeight.w700) : _en(24, 30, FontWeight.w700);

  static TextStyle _en(
    double size,
    double lineHeight,
    FontWeight weight, {
    String family = AppTheme.latinFont,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    leadingDistribution: TextLeadingDistribution.even,
    letterSpacing: 0,
    fontWeight: weight,
    fontVariations: family == AppTheme.latinFont
        ? AppTheme.opticalSize(size)
        : null,
  );

  static TextStyle _ar(double size, double lineHeight, FontWeight weight) =>
      TextStyle(
        fontFamily: AppTheme.arabicFont,
        fontSize: size,
        height: lineHeight / size,
        leadingDistribution: TextLeadingDistribution.even,
        letterSpacing: 0,
        fontWeight: weight,
      );
}
