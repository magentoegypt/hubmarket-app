import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/app/theme/theme_mode_controller.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';

import '../support/fakes.dart';

ProviderContainer _container([FakeLocalCache? cache]) {
  final c = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(cache ?? FakeLocalCache()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('ThemeModeController', () {
    test('defaults to light (white), not system', () {
      expect(_container().read(themeModeProvider), ThemeMode.light);
    });

    test('honours a persisted choice', () {
      final cache = FakeLocalCache()..writeString(kThemeModePrefKey, 'dark');
      expect(_container(cache).read(themeModeProvider), ThemeMode.dark);
    });

    test('set persists the choice', () async {
      final cache = FakeLocalCache();
      final container = _container(cache);
      await container.read(themeModeProvider.notifier).set(ThemeMode.system);
      expect(container.read(themeModeProvider), ThemeMode.system);
      expect(cache.readString(kThemeModePrefKey), 'system');
    });
  });
}
