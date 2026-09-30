import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the Arabic translation against drifting from the English template:
/// gen-l10n falls back to English for a missing key without failing, and it
/// accepts a translation that drops a placeholder or a plural.
void main() {
  final en = _readArb('lib/l10n/app_en.arb');
  final ar = _readArb('lib/l10n/app_ar.arb');

  test('app_en.arb and app_ar.arb have the same message keys', () {
    final enKeys = _messageKeys(en);
    final arKeys = _messageKeys(ar);
    expect(
      enKeys.difference(arKeys),
      isEmpty,
      reason: 'English messages missing from app_ar.arb',
    );
    expect(
      arKeys.difference(enKeys),
      isEmpty,
      reason: 'Arabic messages without an English template',
    );
  });

  test('every placeholder of a message is used by its Arabic translation', () {
    final missing = <String>[];
    for (final key in _messageKeys(en)) {
      final translation = ar[key];
      if (translation is! String) continue; // reported by the keys test
      for (final name in _placeholders(en, key)) {
        if (!_usesPlaceholder(translation, name)) missing.add('$key: {$name}');
      }
    }
    expect(missing, isEmpty, reason: 'placeholders missing in app_ar.arb');
  });

  test('a message that is a plural in English is a plural in Arabic', () {
    final single = <String>[
      for (final key in _messageKeys(en))
        if (_isPlural(en[key]) && ar[key] is String && !_isPlural(ar[key])) key,
    ];
    expect(single, isEmpty, reason: 'single-form Arabic plurals');
  });

  test('the checks see a missing placeholder and a missing plural', () {
    expect(_usesPlaceholder('{count} نتيجة', 'count'), isTrue);
    expect(_usesPlaceholder('{count, plural, other{نتائج}}', 'count'), isTrue);
    expect(_usesPlaceholder('نتائج «{query}»', 'count'), isFalse);
    expect(_usesPlaceholder('{counter}', 'count'), isFalse);
    expect(_isPlural('{count, plural, =1{a} other{b}}'), isTrue);
    expect(_isPlural('Subtotal ({count, plural, other{b}})'), isTrue);
    expect(_isPlural('{count} items'), isFalse);
  });
}

/// The ARB at [path], relative to the package root (`flutter test`'s working
/// directory).
Map<String, dynamic> _readArb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Message keys: everything but `@key` metadata and `@@locale`.
Set<String> _messageKeys(Map<String, dynamic> arb) =>
    arb.keys.where((key) => !key.startsWith('@')).toSet();

/// The placeholders the English template declares for [key].
Iterable<String> _placeholders(Map<String, dynamic> arb, String key) {
  final meta = arb['@$key'];
  if (meta is! Map<String, dynamic>) return const [];
  final placeholders = meta['placeholders'];
  if (placeholders is! Map<String, dynamic>) return const [];
  return placeholders.keys;
}

/// Whether [message] uses [name] — as `{name}` or as the argument of a
/// `{name, plural, …}` / `{name, select, …}`.
bool _usesPlaceholder(String message, String name) =>
    RegExp('\\{\\s*${RegExp.escape(name)}\\s*[,}]').hasMatch(message);

bool _isPlural(Object? message) =>
    message is String &&
    RegExp(r'\{\s*\w+\s*,\s*plural\s*,').hasMatch(message);
