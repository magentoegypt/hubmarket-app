import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Push needs the notification permission on Android 13+. The manifest used to
/// strip it (`tools:node="remove"`) while the app had no Firebase config; now a
/// build with the config asks for it, so it has to stay declared, or the app
/// would register for pushes it can never show.
void main() {
  test('the Android manifest declares POST_NOTIFICATIONS and keeps it', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final declarations = RegExp(
      r'<uses-permission\b[^>]*POST_NOTIFICATIONS[^>]*>',
    ).allMatches(manifest).map((m) => m.group(0)!).toList();

    expect(declarations, hasLength(1));
    expect(declarations.single, isNot(contains('tools:node')));
  });
}
