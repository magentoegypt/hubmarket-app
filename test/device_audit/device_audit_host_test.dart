import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/device_audit/harness.dart';
import '../../integration_test/device_audit/scenes.dart';
import '../support/fonts.dart';

/// The device audit's scenes (integration_test/device_audit/), mounted in the
/// test renderer at the size of the test phone — a Redmi at 720 x 1640 px, 2x,
/// so 360 x 820 dp, a 34 dp status bar on top and a 47 dp navigation bar below —
/// instead of on the phone. It is the quick loop: every scene must mount in
/// English and Arabic without a layout overflow or any other framework error,
/// and its captures land in build/device_audit_host/ to look at.
///
/// The Figma frames are 390 dp wide, so this is also the width check: what fits
/// in 390 may not fit in 360.
///
///   flutter test test/device_audit/device_audit_host_test.dart
///   flutter test test/device_audit/device_audit_host_test.dart --dart-define=AUDIT_ONLY=E21
///
/// The size can be changed with AUDIT_W, AUDIT_H (in px) and AUDIT_DPR.
void main() {
  const only = String.fromEnvironment('AUDIT_ONLY');
  const width = int.fromEnvironment('AUDIT_W', defaultValue: 720);
  const height = int.fromEnvironment('AUDIT_H', defaultValue: 1640);
  final ratio = double.parse(
    const String.fromEnvironment('AUDIT_DPR', defaultValue: '2'),
  );
  final wanted = only
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  setUpAll(() async {
    await loadAppFonts();
    // The first network image of the process creates the image cache manager,
    // which asks the path_provider plugin for a directory; the test renderer
    // has no plugins (the phone does), and the error would land on whichever
    // scene happens to be up.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  for (final scene in allScenes()) {
    if (wanted.isNotEmpty && !wanted.any(scene.id.contains)) continue;
    for (final locale in scene.locales) {
      testWidgets('${scene.id} ($locale)', (tester) async {
        const bars = FakeViewPadding(top: 68, bottom: 94);
        tester.view
          ..physicalSize = Size(width.toDouble(), height.toDouble())
          ..devicePixelRatio = ratio
          ..padding = bars
          ..viewPadding = bars;
        addTearDown(tester.view.reset);

        late SceneRun run;
        await withRealShadows(() async {
          run = await runScene(tester, scene, locale, (name, boundary) async {
            // Asset images decode asynchronously; finish them first. A
            // network image never answers in the test renderer, so waiting
            // for one would hang the sweep: those are left as they are.
            await tester.runAsync(() async {
              for (final element in find.byType(Image).evaluate()) {
                final image = (element.widget as Image).image;
                if (_isNetwork(image)) continue;
                await precacheImage(image, element);
              }
            });
            await tester.pump();
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage(pixelRatio: ratio);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              File('build/device_audit_host/$name.png')
                ..createSync(recursive: true)
                ..writeAsBytesSync(png!.buffer.asUint8List());
            });
          });
        });
        expect(run.captures, isNotEmpty, reason: run.errors.join('\n'));
        expect(run.errors, isEmpty, reason: run.errors.join('\n'));
      });
    }
  }
}

bool _isNetwork(ImageProvider<Object> provider) {
  final inner = provider is ResizeImage ? provider.imageProvider : provider;
  return inner is NetworkImage || inner is CachedNetworkImageProvider;
}
