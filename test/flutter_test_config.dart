import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file.
///
/// UI audit mode, `flutter test --dart-define=UI_AUDIT=true`, gives every test the
/// iPhone safe-area insets the Figma frames include: a 47 px status bar on top and a 34 px home
/// indicator at the bottom. The screen captures in build/test_screens (see captureScreen in
/// support/fonts.dart) then line up with the frames, so `tool/ui_audit/pairs.py` can put each next to
/// its Figma frame and a header or a bottom button sits at the same y in both. Without the flag
/// nothing changes: the insets are zero and the other tests see what they always saw.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  if (const bool.fromEnvironment('UI_AUDIT')) {
    setUp(() {
      final view = TestWidgetsFlutterBinding.instance.platformDispatcher.implicitView!;
      const insets = FakeViewPadding(top: 47, bottom: 34);
      view
        ..padding = insets
        ..viewPadding = insets;
    });
  }
  await testMain();
}
