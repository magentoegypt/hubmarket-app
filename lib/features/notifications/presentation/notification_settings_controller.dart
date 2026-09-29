import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/local_cache.dart';
import '../data/device_token_repository.dart';

/// Persisted key + topic for the push opt-in.
///
/// NB: the key string ('notif_promotions') is mirrored in
/// [DeviceTokenSync.register]'s opt-out gate — keep them in sync.
const String kPromoPrefKey = 'notif_promotions';
const String kPromoTopic = 'promotions';

/// Whether push is enabled (default on) — the Edit Profile / Settings toggle.
/// Persisted locally; on toggle it (un)subscribes the promo FCM topic AND
/// (un)registers this device's token with the backend, so turning push off
/// removes the device from targeted (order/welcome) pushes too. Re-enabling
/// re-binds the token.
class NotificationSettings extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(localCacheProvider).readString(kPromoPrefKey) != 'false';

  Future<void> setPromotions(bool enabled) async {
    state = enabled;
    await ref.read(localCacheProvider).writeString(kPromoPrefKey, '$enabled');
    final deviceToken = ref.read(deviceTokenSyncProvider);
    if (enabled) {
      await NotificationService.instance.subscribeToTopic(kPromoTopic);
      // Persist first (above) so register()'s opt-out gate sees 'true'.
      await deviceToken.register();
    } else {
      // Remove the token from the backend before unsubscribing the topic.
      await deviceToken.unregister();
      await NotificationService.instance.unsubscribeFromTopic(kPromoTopic);
    }
  }
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettings, bool>(NotificationSettings.new);

/// Applies the persisted topic subscriptions at startup (after FCM init). A
/// no-op when FCM is unavailable.
Future<void> applyNotificationTopics(LocalCache cache) async {
  if (cache.readString(kPromoPrefKey) != 'false') {
    await NotificationService.instance.subscribeToTopic(kPromoTopic);
  }
}
