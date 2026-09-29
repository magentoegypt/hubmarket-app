import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_info.dart';
import '../../../core/config/backend_capabilities.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/local_cache.dart';

/// Registers / removes this device's FCM token with the backend, so it can push
/// order and account notifications to one customer rather than to a topic.
///
/// **Hub Market has no endpoint for this yet.** The app this one started from
/// used custom `registerDeviceToken` / `removeDeviceToken` mutations (contract:
/// `docs/backend/notifications-contract.md`); Hub Market's schema has neither.
/// Its `MagentoEgypt_PushNotification` module (storefront branch
/// `claude/add-pushnotification-fcm`) stores devices and sends through FCM but
/// exposes no API for an app to register one. Until it does, both calls are
/// no-ops and [DeviceTokenSync] doesn't reach them
/// ([BackendCapabilities.pushDeviceTokens] is off). Put the operations back
/// here together with the flag.
class DeviceTokenRepository {
  const DeviceTokenRepository();

  Future<void> register({
    required String token,
    required String platform,
    String? appVersion,
  }) async {
    debugPrint('DeviceToken: this backend has no registration endpoint');
  }

  Future<void> remove(String token) async {
    debugPrint('DeviceToken: this backend has no removal endpoint');
  }
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => const DeviceTokenRepository(),
);

/// Orchestrates *when* the device token is (re)registered: app launch + token
/// refresh (wired in `bootstrap`), login (re-binds the guest token to the
/// customer), store/language switch (refreshes the locale), and logout (removes
/// it while the bearer is still valid).
///
/// Every call returns at once while the backend can't take tokens
/// ([BackendCapabilities.pushDeviceTokens]) — which also spares logout the wait
/// for an iOS APNs token that [NotificationService.token] would otherwise do.
class DeviceTokenSync {
  DeviceTokenSync(this._ref);

  final Ref _ref;

  bool get _enabled => _ref.read(backendCapabilitiesProvider).pushDeviceTokens;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Register the current FCM token (no-op when the backend can't take it, FCM
  /// is off / the token is null, or the user has turned push OFF). The opt-out
  /// check makes the launch / login / token-refresh heartbeat respect the Edit
  /// Profile / Settings toggle — otherwise it would silently re-add a token the
  /// user removed.
  Future<void> register() async {
    if (!_enabled) return;
    // Persisted by NotificationSettings under 'notif_promotions' (the push
    // opt-in). Absent/anything-but-'false' means enabled (default on). Read
    // defensively — if the cache isn't wired (e.g. in tests) treat as enabled.
    try {
      if (_ref.read(localCacheProvider).readString('notif_promotions') ==
          'false') {
        return;
      }
    } catch (_) {
      // Cache unavailable — fall through and register (default-on behaviour).
    }
    final token = await NotificationService.instance.token();
    if (token == null || token.isEmpty) return;
    final version = _ref
        .read(appVersionProvider)
        .maybeWhen(data: (v) => v, orElse: () => null);
    await _ref
        .read(deviceTokenRepositoryProvider)
        .register(token: token, platform: _platform, appVersion: version);
  }

  /// Remove the current token. Call **before** revoking the bearer on logout so
  /// the backend can scope the delete to the authenticated customer.
  Future<void> unregister() async {
    if (!_enabled) return;
    final token = await NotificationService.instance.token();
    if (token == null || token.isEmpty) return;
    await _ref.read(deviceTokenRepositoryProvider).remove(token);
  }
}

final deviceTokenSyncProvider = Provider<DeviceTokenSync>(
  (ref) => DeviceTokenSync(ref),
);
