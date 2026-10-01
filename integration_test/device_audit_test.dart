import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'device_audit/harness.dart';
import 'device_audit/scenes.dart';

/// Mounts every Figma screen on the phone, in English and Arabic, and captures
/// it with `binding.takeScreenshot` for comparison with the frame (see
/// docs/ui-audit.md, "Check on a device"). Each screen is the real widget
/// with the fakes of the widget tests (no login, no network, nothing sent to
/// the server), on the phone's own surface: its size, pixel ratio and system
/// bars are not overridden, which is the point.
///
/// Run via tool/device_audit.sh; the captures land in build/device_audit. A
/// framework error raised while a screen is up (a layout overflow above all)
/// is printed as `AUDIT ... !` and listed in the summary.
///
///   AUDIT_ONLY=E21,E22   only the scenes whose id contains one of these
///   AUDIT_LOCALES=ar     only this locale (default en,ar)
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const only = String.fromEnvironment('AUDIT_ONLY');
  const localesArg = String.fromEnvironment(
    'AUDIT_LOCALES',
    defaultValue: 'en,ar',
  );

  testWidgets('device audit', (tester) async {
    final wanted = only
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final locales = localesArg.split(',').map((e) => e.trim()).toList();

    // On Android the Flutter surface has to be converted to an image before
    // takeScreenshot can read it.
    await tester.pumpWidget(const SizedBox.shrink());
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
    // ignore: avoid_print
    print('AUDIT view: ${describeView(tester)}');

    var scenes = 0, captures = 0;
    final broken = <String>[];
    for (final scene in allScenes()) {
      if (wanted.isNotEmpty && !wanted.any(scene.id.contains)) continue;
      for (final locale in scene.locales.where(locales.contains)) {
        final run = await runScene(
          tester,
          scene,
          locale,
          (name, _) => binding.takeScreenshot(name),
        );
        scenes++;
        captures += run.captures.length;
        // ignore: avoid_print
        print(
          'AUDIT ${run.id}: ${run.captures.length} shots, '
          '${run.errors.length} errors',
        );
        for (final error in run.errors.take(6)) {
          // ignore: avoid_print
          print('AUDIT   ! $error');
        }
        if (run.errors.isNotEmpty) broken.add(run.id);
      }
    }
    // ignore: avoid_print
    print(
      'AUDIT done: $scenes scenes, $captures captures, '
      '${broken.length} with errors${broken.isEmpty ? '' : ': ${broken.join(', ')}'}',
    );
  }, timeout: const Timeout(Duration(minutes: 45)));
}
