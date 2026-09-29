import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-aware colour resolvers for text/fills/hairlines that sit **directly on
/// the dark scaffold** (or the white menu drawer). In light mode they return the
/// original Figma tokens unchanged; in dark mode they flip to a legible
/// counterpart.
///
/// Only use these for content painted on the scaffold background. Text placed on
/// a self-contained light surface (a blush [AppColors.surfaceTint] card, a white
/// product card) must keep the fixed [AppColors] tokens — those surfaces stay
/// light in both modes, so their dark text is already correct.
extension HubThemeX on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// Primary heading/body text on the scaffold (`inkHeading` → white).
  Color get scaffoldHeading =>
      isDarkMode ? Colors.white : AppColors.inkHeading;

  /// Secondary/muted text on the scaffold (`inkMuted` → light grey).
  Color get scaffoldMuted =>
      isDarkMode ? const Color(0xFFAEB6C2) : AppColors.inkMuted;

  /// Faint text (version strings, trailing values) on the scaffold.
  Color get scaffoldFaint => isDarkMode ? Colors.white38 : AppColors.inkFaint;

  /// Filled input / preference-row background on the scaffold
  /// (`surfaceMuted` → translucent white). Mirrors the global
  /// `inputDecorationTheme` dark fill.
  Color get fieldFill => isDarkMode ? Colors.white10 : AppColors.surfaceMuted;

  /// Hairline dividers / card outlines on the scaffold (`borderDefault`).
  Color get hairline => isDarkMode ? Colors.white24 : AppColors.borderDefault;

  /// Full-bleed 8px section separator band on the scaffold (`surfaceMuted`).
  Color get sectionBand => isDarkMode ? Colors.white10 : AppColors.surfaceMuted;
}
