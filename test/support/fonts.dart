import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';

/// Loads the app's bundled fonts (DM Sans, Tajawal, Playfair Display, the Lucide
/// icon font) and the Material icon font into the test engine, so golden-style captures render
/// real glyphs instead of the test font's boxes. Call from `setUpAll`.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> assets) async {
    final loader = FontLoader(family);
    for (final asset in assets) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  }

  await load(AppTheme.latinFont, ['assets/fonts/DMSans.ttf']);
  await load(AppTheme.arabicFont, [
    'assets/fonts/Tajawal-Regular.ttf',
    'assets/fonts/Tajawal-Medium.ttf',
    'assets/fonts/Tajawal-Bold.ttf',
    'assets/fonts/Tajawal-ExtraBold.ttf',
  ]);
  await load(AppTheme.displayFont, ['assets/fonts/PlayfairDisplay.ttf']);
  // The Figma icon set (lib/app/theme/hub_icons.dart).
  await load('Lucide', ['assets/fonts/Lucide.ttf']);

  final icons = _materialIconsFont();
  if (icons != null) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

/// `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`
/// — found from FLUTTER_ROOT when set, else by walking up from the test
/// runner's own executable (which lives under the same `bin/cache`).
File? _materialIconsFont() {
  const relative = 'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?) root,
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 8; i++) {
    roots.add(dir.path);
    dir = dir.parent;
  }
  roots.add(r'C:\flutter');
  for (final root in roots) {
    final file = File('$root/$relative');
    if (file.existsSync()) return file;
  }
  return null;
}

/// Runs [body] with real (blurred) shadows. Widget tests draw shadows without
/// blur for stable goldens, which makes a capture misleading next to a frame;
/// the test binding expects the flag back on when the test ends.
Future<void> withRealShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}

/// Writes the [RepaintBoundary] behind [boundaryKey] to
/// `build/test_screens/<name>.png` — a visual record for review against the
/// Figma frames. `build/` is gitignored and nothing is asserted on the image.
Future<void> captureScreen(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  // Asset images decode asynchronously; finish them before the capture.
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('build/test_screens/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}
