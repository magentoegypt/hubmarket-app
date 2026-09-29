import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Builds the app [ThemeData] from Figma tokens with locale-aware typography
/// (Figma "01 · Cover & Foundations"): DM Sans for Latin (EN), Tajawal for
/// Arabic (AR). Playfair Display is the EN Display / Heading 1 face — applied
/// where those styles are used ([AppTextStyles]), never as the base font, and
/// never in Arabic (it has no Arabic glyphs).
abstract final class AppTheme {
  static const String latinFont = 'DM Sans';
  static const String arabicFont = 'Tajawal';
  static const String displayFont = 'Playfair Display';

  static String fontFor(String languageCode) =>
      languageCode == 'ar' ? arabicFont : latinFont;

  /// DM Sans is a variable font with an optical-size (`opsz`, 9–40) axis whose
  /// default is 9. Figma and the storefront (CSS `font-optical-sizing: auto`)
  /// draw each size at its own optical size; the engine does not, so the text
  /// theme pins `opsz` to every style's size. Text that only overrides
  /// `fontSize` inherits the body style's optical size — close enough.
  static List<FontVariation> opticalSize(double fontSize) => <FontVariation>[
    FontVariation('opsz', fontSize.clamp(9, 40).toDouble()),
  ];

  static TextStyle? _withOpticalSize(TextStyle? style) {
    final size = style?.fontSize;
    return size == null ? style : style!.copyWith(fontVariations: opticalSize(size));
  }

  static TextTheme _opticalSizes(TextTheme t) => t.copyWith(
    displayLarge: _withOpticalSize(t.displayLarge),
    displayMedium: _withOpticalSize(t.displayMedium),
    displaySmall: _withOpticalSize(t.displaySmall),
    headlineLarge: _withOpticalSize(t.headlineLarge),
    headlineMedium: _withOpticalSize(t.headlineMedium),
    headlineSmall: _withOpticalSize(t.headlineSmall),
    titleLarge: _withOpticalSize(t.titleLarge),
    titleMedium: _withOpticalSize(t.titleMedium),
    titleSmall: _withOpticalSize(t.titleSmall),
    bodyLarge: _withOpticalSize(t.bodyLarge),
    bodyMedium: _withOpticalSize(t.bodyMedium),
    bodySmall: _withOpticalSize(t.bodySmall),
    labelLarge: _withOpticalSize(t.labelLarge),
    labelMedium: _withOpticalSize(t.labelMedium),
    labelSmall: _withOpticalSize(t.labelSmall),
  );

  static ThemeData light(String languageCode) =>
      _build(languageCode, Brightness.light);
  static ThemeData dark(String languageCode) =>
      _build(languageCode, Brightness.dark);

  static ThemeData _build(String languageCode, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandPrimary,
      brightness: brightness,
      primary: AppColors.brandPrimary,
      secondary: AppColors.accent,
      error: AppColors.accentSale,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      fontFamily: fontFor(languageCode),
    );
    // Tajawal ships as static weights, so only the Latin face needs this.
    final latin = languageCode != 'ar';

    return base.copyWith(
      textTheme: latin ? _opticalSizes(base.textTheme) : base.textTheme,
      primaryTextTheme: latin
          ? _opticalSizes(base.primaryTextTheme)
          : base.primaryTextTheme,
      // Edge-swipe back on every platform (CL042-DEV11). Android's default
      // Zoom transition has no back gesture at all, so a pushed screen could
      // only be left through the app-bar arrow. The Cupertino builder brings
      // the drag-from-the-edge dismissal with it, and its detector sits on the
      // *directional* start edge: swipe in from the left in English, from the
      // right in Arabic, no manual flipping (see [[rtl-arrow-double-flip]] for
      // why manual mirroring is a trap here).
      //
      // Do NOT swap Android to PredictiveBackPageTransitionsBuilder. It ships
      // no Flutter-side drag detector at all — it only renders the system's
      // predictive-back preview — so on Android 11 (API 30), where predictive
      // back does not exist, it would help nothing, and on any 3-button-nav
      // device it would remove the in-app swipe outright. For the same reason
      // `android:enableOnBackInvokedCallback` stays out of AndroidManifest.xml:
      // it is a no-op on API 30, which is the version QA tests on.
      //
      // The Cupertino detector is necessary but not sufficient: it is a 20 px
      // strip flush against the screen edge, inside the band Android reserves
      // for system navigation, and it is disabled outright on a first route.
      // BackSwipeDetector (app/shell/back_swipe.dart) covers both gaps.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: brightness == Brightness.light
          ? Colors.white
          : AppColors.surfaceDark,
      appBarTheme: AppBarTheme(
        backgroundColor: brightness == Brightness.light
            ? Colors.white
            : AppColors.surfaceDark,
        // Ink (near-black) titles + leading/action icons per QA — the navy
        // brand colour stays on the logo and buttons, not the page titles.
        // Screens that render the BrandLogo image are unaffected.
        // In dark mode the ink title would be near-invisible on the dark surface
        // (QA: "the page title is still not clearly visible in Dark Mode"), so
        // flip it to white — this fixes every text AppBar title app-wide.
        foregroundColor: brightness == Brightness.light
            ? AppColors.inkHeading
            : Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      // Figma form fields: filled grey (surface/alt), rounded, no hard border,
      // navy focus ring. Applies to every TextField/TextFormField app-wide.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brightness == Brightness.light
            ? const Color(0xFFF3F4F6) // surface/alt
            : Colors.white10,
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)), // text/muted
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AppColors.brandPrimary,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
