import 'dart:io';
import 'package:image/image.dart' as img;

// Builds launcher icons from the brand logo's Z-monogram (the top mark, minus
// the HUB MARKET wordmark), rendered WHITE on the brand burgundy (#9E1B3F) to match
// the splash. The logo is high-res so the icon is crisp.
//   dart run tool/icon_gen.dart   then   dart run flutter_launcher_icons
const burgundy = [0x9E, 0x1B, 0x3F];

void main() {
  final logo = img.decodePng(File('assets/branding/logo.png').readAsBytesSync())!;
  // The monogram occupies the top ~66%; the wordmark sits below. Find the
  // tight bounding box of non-transparent pixels in that top region only.
  final cutoff = (logo.height * 0.66).round();
  int minX = logo.width, minY = logo.height, maxX = 0, maxY = 0;
  for (var y = 0; y < cutoff; y++) {
    for (var x = 0; x < logo.width; x++) {
      if (logo.getPixel(x, y).a > 16) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  final mono = img.copyCrop(logo,
      x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
  stdout.writeln('monogram bbox: ${mono.width}x${mono.height}');

  // Scale to fit `box`, keep aspect, recolor white (alpha = glyph mask).
  img.Image whiteGlyph(int box) {
    final scale = box / (mono.width > mono.height ? mono.width : mono.height);
    final g = img.copyResize(mono,
        width: (mono.width * scale).round(),
        height: (mono.height * scale).round(),
        interpolation: img.Interpolation.cubic);
    for (final p in g) {
      p.r = 255; p.g = 255; p.b = 255; // white; anti-aliased alpha preserved
    }
    return g;
  }

  img.Image canvas(bool burgundyBg) {
    final c = img.Image(width: 1024, height: 1024, numChannels: 4);
    img.fill(c, color: burgundyBg
        ? img.ColorRgb8(burgundy[0], burgundy[1], burgundy[2])
        : img.ColorRgba8(0, 0, 0, 0));
    return c;
  }

  void paste(img.Image dst, img.Image g) => img.compositeImage(dst, g,
      dstX: (dst.width - g.width) ~/ 2, dstY: (dst.height - g.height) ~/ 2);

  final main = canvas(true);
  paste(main, whiteGlyph(720)); // ~70% — iOS + Android legacy
  File('assets/branding/app_icon.png').writeAsBytesSync(img.encodePng(main));

  final fg = canvas(false);
  paste(fg, whiteGlyph(600)); // more padding for the adaptive mask
  File('assets/branding/app_icon_foreground.png')
      .writeAsBytesSync(img.encodePng(fg));
  stdout.writeln('wrote app_icon.png + app_icon_foreground.png from logo');
}
