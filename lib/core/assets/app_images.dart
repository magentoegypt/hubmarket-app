/// Typed asset path constants. Files are committed under `assets/` and declared
/// in `pubspec.yaml`. Widgets should use `Image.asset(..., errorBuilder:)` so a
/// missing file degrades to a neutral placeholder (no fabricated imagery).
abstract final class AppImages {
  static const String _branding = 'assets/branding';
  static const String _images = 'assets/images';

  /// Full Hub Market logo (Z-mark + wordmark) — white on burgundy Launch splash.
  static const String logo = '$_branding/logo.png';

  /// Z-monogram mark used in the icon + wordmark lockup.
  static const String favicon = '$_branding/favicon.ico';

  /// Home hero / Welcome splash visual.
  static const String banner = '$_images/banner.jpg';

  /// Sample product imagery (assigned round-robin in dev/preview). Real
  /// catalogue media binds from Magento GraphQL at runtime.
  static const List<String> products = <String>[
    '$_images/test_product.jpg',
    '$_images/test_product_2.jpg',
    '$_images/test_product_3.jpg',
    '$_images/test_product_4.jpg',
  ];
}
