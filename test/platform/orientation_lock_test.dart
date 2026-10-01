import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app is portrait only on phones: every Figma frame is a portrait phone
/// frame, and the Welcome screen overflowed when a phone was held sideways. The
/// lock lives in the platform files (so the native launch screen holds it too);
/// these tests keep a later edit of either file from dropping it.
void main() {
  test('the Android activity is locked to portrait', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final activity = RegExp(
      r'<activity\b[^>]*android:name="\.MainActivity"[^>]*>',
    ).firstMatch(manifest);

    expect(activity, isNotNull, reason: 'MainActivity is declared');
    expect(
      activity!.group(0),
      contains('android:screenOrientation="portrait"'),
    );
  });

  test('the iPhone is limited to portrait', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final block = RegExp(
      r'<key>UISupportedInterfaceOrientations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(plist);

    expect(block, isNotNull, reason: 'the iPhone orientations are listed');
    final orientations = RegExp(
      r'<string>(.*?)</string>',
    ).allMatches(block!.group(1)!).map((m) => m.group(1)).toList();
    expect(orientations, ['UIInterfaceOrientationPortrait']);
  });
}
