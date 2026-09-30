import 'package:flutter/foundation.dart';

/// The store's rules for a new password (Stores › Configuration › Customers ›
/// Customer Configuration › Password Options), from core `storeConfig`
/// `minimum_password_length` and `required_character_classes_number` — so the
/// app checks and describes exactly what Magento will enforce, instead of a
/// copy of today's settings (QA02).
@immutable
class PasswordPolicy {
  const PasswordPolicy({required this.minLength, required this.requiredClasses});

  /// The policy in a `storeConfig` answer; null when it carries no usable
  /// minimum length (the fields are Strings on the wire).
  static PasswordPolicy? fromStoreConfig(Map<String, dynamic> json) {
    final min = _int(json['minimum_password_length']);
    if (min == null || min < 1) return null;
    final classes = _int(json['required_character_classes_number']) ?? 1;
    return PasswordPolicy(minLength: min, requiredClasses: classes.clamp(1, 4));
  }

  /// Characters a password needs at least, counted as Magento counts them
  /// (code points).
  final int minLength;

  /// How many of Magento's four character classes — lower case, upper case,
  /// digits and special characters — a password must mix (1–4).
  final int requiredClasses;

  static final List<RegExp> _classes = [
    RegExp('[0-9]'),
    RegExp('[A-Z]'),
    RegExp('[a-z]'),
    RegExp('[^a-zA-Z0-9]'),
  ];

  /// The character classes [value] uses, as Magento's
  /// `AccountManagement::makeRequiredCharactersCheck` counts them.
  static int classesIn(String value) =>
      _classes.where((re) => re.hasMatch(value)).length;

  /// Whether Magento will accept [value] as a new password.
  bool accepts(String value) =>
      value.runes.length >= minLength && classesIn(value) >= requiredClasses;

  static int? _int(Object? value) => switch (value) {
    final int n => n,
    final String s => int.tryParse(s.trim()),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is PasswordPolicy &&
      other.minLength == minLength &&
      other.requiredClasses == requiredClasses;

  @override
  int get hashCode => Object.hash(minLength, requiredClasses);

  @override
  String toString() => 'PasswordPolicy($minLength, $requiredClasses classes)';
}
