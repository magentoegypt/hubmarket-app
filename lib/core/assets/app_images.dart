/// Typed asset path constants. Files are committed under `assets/` and declared
/// in `pubspec.yaml`. Widgets should use `Image.asset(..., errorBuilder:)` so a
/// missing file degrades to a neutral placeholder (no fabricated imagery).
///
/// Marketing imagery (hero banners, promos, category images) is NOT bundled —
/// it comes from Magento admin through GraphQL so it can change without an app
/// update. Only the brand artwork lives here.
abstract final class AppImages {
  static const String _branding = 'assets/branding';

  /// Hub Market logo lockup, positive (navy + orange) for light surfaces.
  static const String logo = '$_branding/logo.png';

  /// Hub Market logo lockup, reversed (white + orange) for navy / dark surfaces.
  static const String logoReversed = '$_branding/logo_reversed.png';

  /// App icon artwork (navy tile) — used by in-app "about" surfaces.
  static const String appIcon = '$_branding/app_icon.png';
}
