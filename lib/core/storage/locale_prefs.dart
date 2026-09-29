import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's active store-view language (`en` / `ar`).
class LocalePrefs {
  LocalePrefs(this._prefs);

  final SharedPreferences _prefs;
  static const String _localeKey = 'active_locale';

  String? read() => _prefs.getString(_localeKey);
  Future<void> write(String locale) => _prefs.setString(_localeKey, locale);
}

/// Overridden in `bootstrap()` once SharedPreferences is initialised.
final localePrefsProvider = Provider<LocalePrefs>(
  (ref) => throw UnimplementedError(
    'localePrefsProvider must be overridden in bootstrap()',
  ),
);
