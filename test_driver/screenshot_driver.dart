import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver half of the store-listing screenshot capture. Writes each PNG the
/// test hands over (via `binding.takeScreenshot(name)`) into SHOT_OUT_DIR
/// (build/screenshots/ios when unset), which tool/ios_screenshots.sh then
/// normalises to the App Store slot size and tool/android_screenshots.sh fits
/// to Google Play's.
Future<void> main() async {
  final outDir =
      Platform.environment['SHOT_OUT_DIR'] ?? 'build/screenshots/ios';
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          final file = File('$outDir/$name.png');
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes);
          stdout.writeln('captured ${file.path} (${bytes.length} bytes)');
          return true;
        },
  );
}
