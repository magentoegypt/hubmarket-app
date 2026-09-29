import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Driver half of the App Store screenshot capture. Writes each PNG the test
/// hands over (via `binding.takeScreenshot(name)`) into build/screenshots/ios/,
/// which tool/ios_screenshots.sh then normalises to the App Store slot size.
Future<void> main() async {
  await integrationDriver(
    onScreenshot: (
      String name,
      List<int> bytes, [
      Map<String, Object?>? args,
    ]) async {
      final file = File('build/screenshots/ios/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      stdout.writeln('captured ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
