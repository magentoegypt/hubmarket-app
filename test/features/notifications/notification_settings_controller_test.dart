import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';

import '../../support/fakes.dart';

ProviderContainer _container(FakeLocalCache cache) {
  final container = ProviderContainer(
    overrides: [localCacheProvider.overrideWithValue(cache)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('NotificationSettings', () {
    test('defaults to enabled when nothing is persisted', () {
      final container = _container(FakeLocalCache());
      expect(container.read(notificationSettingsProvider), isTrue);
    });

    test('reads a persisted disabled flag', () {
      final cache = FakeLocalCache();
      cache.writeString(kPromoPrefKey, 'false');
      final container = _container(cache);
      expect(container.read(notificationSettingsProvider), isFalse);
    });

    test('setPromotions persists the new value', () async {
      final cache = FakeLocalCache();
      final container = _container(cache);
      final notifier = container.read(notificationSettingsProvider.notifier);

      await notifier.setPromotions(false);
      expect(container.read(notificationSettingsProvider), isFalse);
      expect(cache.readString(kPromoPrefKey), 'false');

      await notifier.setPromotions(true);
      expect(container.read(notificationSettingsProvider), isTrue);
      expect(cache.readString(kPromoPrefKey), 'true');
    });
  });
}
