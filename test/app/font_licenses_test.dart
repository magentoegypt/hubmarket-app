import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/font_licenses.dart';
import 'package:hubmarket_app/app/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled font family carries its OFL text', () async {
    final entries = await fontLicenseEntries().toList();

    expect(
      entries.expand((e) => e.packages),
      unorderedEquals(<String>[
        AppTheme.latinFont,
        AppTheme.arabicFont,
        AppTheme.displayFont,
      ]),
    );
    for (final entry in entries) {
      final text = entry.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL Open Font License'), reason: '${entry.packages}');
    }
  });

  test('the theme fonts are the ones pubspec bundles', () async {
    final manifest = jsonDecode(
      await rootBundle.loadString('FontManifest.json'),
    ) as List<dynamic>;
    // The app's own families (package fonts are prefixed `packages/<name>/`).
    final families = {
      for (final entry in manifest.cast<Map<String, dynamic>>())
        if (!(entry['family'] as String).startsWith('packages/'))
          entry['family'] as String,
    };
    expect(
      families,
      unorderedEquals(<String>[
        'MaterialIcons',
        AppTheme.latinFont,
        AppTheme.arabicFont,
        AppTheme.displayFont,
      ]),
    );
  });
}
