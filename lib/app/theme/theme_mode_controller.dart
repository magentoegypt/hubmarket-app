import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/storage/local_cache.dart';

const String kThemeModePrefKey = 'theme_mode';

/// App appearance: White (light) / Black (dark) / System. Persisted locally and
/// **defaults to light** — the app's white design — regardless of the OS dark
/// setting, so it never goes dark unless the user opts in.
///
/// The switch is a developer tool (Settings shows it in dev and staging
/// only), so the customer build stays light even when an earlier build
/// stored another choice — with no switch, it could never be undone.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    if (!ref.watch(developerToolsProvider)) return ThemeMode.light;
    return _parse(ref.read(localCacheProvider).readString(kThemeModePrefKey));
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref
        .read(localCacheProvider)
        .writeString(kThemeModePrefKey, mode.name);
  }

  static ThemeMode _parse(String? value) => switch (value) {
    'dark' => ThemeMode.dark,
    'system' => ThemeMode.system,
    _ => ThemeMode.light, // default = white
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
