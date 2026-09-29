import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/app_info.dart';
import '../../../core/config/hubapp_account.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/graphql/hubapp_operation.dart';
import '../../../core/hubapp/hubapp.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/local_cache.dart';
import '../../../core/store/store_controller.dart';
import '../presentation/notification_settings_controller.dart';

/// `hmRegisterDevice` / `hmUnregisterDevice` (`MagentoEgypt_HubAppAccount`).
///
/// The platform is written into the document — one per platform — because
/// Magento answers a variable of an unknown enum type (`HmPlatform`) with HTTP
/// 500 while the module is missing, instead of "Cannot query field".
abstract final class DeviceTokenQueries {
  static const String registerAndroid = r'''
mutation HmRegisterDeviceAndroid($token: String!, $appVersion: String) {
  hmRegisterDevice(
    input: { token: $token, platform: ANDROID, app_version: $appVersion }
  ) {
    success
  }
}
''';

  static const String registerIos = r'''
mutation HmRegisterDeviceIos($token: String!, $appVersion: String) {
  hmRegisterDevice(
    input: { token: $token, platform: IOS, app_version: $appVersion }
  ) {
    success
  }
}
''';

  static const String unregister = r'''
mutation HmUnregisterDevice($token: String!) {
  hmUnregisterDevice(input: { token: $token }) { success }
}
''';
}

/// Registers / removes this device's FCM token with the backend, so it can
/// push order and account notifications to one customer rather than to a
/// topic (`MagentoEgypt_PushNotification`'s device table).
///
/// Both go through the token client: with a customer bearer the backend binds
/// the device to that customer, without one it keeps a guest device. Both are
/// idempotent. Throw [HubAppMissing] when the server lacks the module, a
/// `Failure` otherwise.
class DeviceTokenRepository {
  DeviceTokenRepository(this._client);

  final GraphQLClient _client;

  /// False when the server refused the input (the only case it says so).
  Future<bool> register({
    required String token,
    required HmPlatform platform,
    String? appVersion,
  }) async {
    final data = await runHubAppOperation(
      _client,
      platform == HmPlatform.ios
          ? DeviceTokenQueries.registerIos
          : DeviceTokenQueries.registerAndroid,
      variables: {'token': token, 'appVersion': appVersion},
      mutation: true,
    );
    return (data['hmRegisterDevice'] as Map<String, dynamic>?)?['success'] ==
        true;
  }

  Future<bool> remove(String token) async {
    final data = await runHubAppOperation(
      _client,
      DeviceTokenQueries.unregister,
      variables: {'token': token},
      mutation: true,
    );
    return (data['hmUnregisterDevice'] as Map<String, dynamic>?)?['success'] ==
        true;
  }
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => DeviceTokenRepository(ref.watch(graphqlClientProvider)),
);

/// This device's FCM registration token — null while FCM is off (no Firebase
/// config is bundled yet) or not ready. A provider so tests can hand one in.
final fcmTokenProvider = Provider<Future<String?> Function()>(
  (ref) => NotificationService.instance.token,
);

/// The platform the token belongs to; null on a platform that has none.
final devicePlatformProvider = Provider<HmPlatform?>(
  (ref) => HmPlatform.current,
);

/// Orchestrates *when* the device token is (re)registered: app launch and
/// token refresh, a store/language switch (the backend keeps the store view a
/// push is written for), and login (re-binds the guest device to the
/// customer) — see [startDeviceTokenSync] and `AuthController` — and when it
/// is removed: logout, while the bearer is still valid, and the push opt-out.
///
/// Every call returns at once unless pushes can reach this device and the
/// backend takes tokens: FCM is up (a Firebase config is bundled — none is
/// yet, so this is dormant) and `HubAppAccount`'s `push` switch is on. FCM is
/// checked first, so nothing else is asked while it is off; that also spares
/// logout the wait for an iOS APNs token that [NotificationService.token]
/// would otherwise do.
class DeviceTokenSync {
  DeviceTokenSync(this._ref, {this.probeWait = const Duration(seconds: 3)});

  final Ref _ref;

  /// How long a call waits for a HubApp probe that is still running (launch,
  /// a store switch) before treating the answer as "not known": Build 1.
  final Duration probeWait;

  Future<bool> _enabled() async {
    if (!_ref.read(pushNotificationsAvailableProvider)) return false;
    // Rather than skip a registration — or, at sign-out, leave the device
    // bound to the customer — wait briefly for a probe that hasn't answered.
    if (_ref.read(hubAppProvider).isLoading) {
      try {
        await _ref.read(hubAppProvider.future).timeout(probeWait);
      } on Object {
        // Still unknown: the features below read as off.
      }
    }
    return _ref.read(hubAppAccountFeaturesProvider).pushDevices;
  }

  /// Register the current FCM token (no-op when disabled — see the class —,
  /// the token is null, or the user has turned push off). The opt-out check
  /// makes the launch / login / refresh heartbeat respect the Settings toggle
  /// — otherwise it would silently re-add a token the user removed.
  Future<void> register() async {
    if (!await _enabled()) return;
    // Persisted by NotificationSettings under 'notif_promotions' (the push
    // opt-in). Absent/anything-but-'false' means enabled (default on). Read
    // defensively — if the cache isn't wired treat as enabled.
    try {
      if (_ref.read(localCacheProvider).readString(kPromoPrefKey) == 'false') {
        return;
      }
    } catch (_) {
      // Cache unavailable — fall through and register (default-on behaviour).
    }
    final platform = _ref.read(devicePlatformProvider);
    if (platform == null) return;
    final token = await _ref.read(fcmTokenProvider)();
    if (token == null || token.isEmpty) return;
    String? version;
    try {
      version = await _ref.read(appSemverProvider.future);
    } catch (_) {
      version = null;
    }
    try {
      await _ref
          .read(deviceTokenRepositoryProvider)
          .register(token: token, platform: platform, appVersion: version);
    } on HubAppMissing {
      _ref.read(hubAppAccountMissingProvider.notifier).mark();
    } on Object catch (error) {
      // Best effort: the next launch, refresh or login registers again.
      debugPrint('DeviceToken: register failed: $error');
    }
  }

  /// Remove the current token. Call **before** revoking the bearer on logout
  /// so the backend switches off this customer's row for the device. Never
  /// throws: signing out must go on.
  Future<void> unregister() async {
    if (!await _enabled()) return;
    final token = await _ref.read(fcmTokenProvider)();
    if (token == null || token.isEmpty) return;
    try {
      await _ref.read(deviceTokenRepositoryProvider).remove(token);
    } on HubAppMissing {
      _ref.read(hubAppAccountMissingProvider.notifier).mark();
    } on Object catch (error) {
      debugPrint('DeviceToken: unregister failed: $error');
    }
  }
}

final deviceTokenSyncProvider = Provider<DeviceTokenSync>(
  (ref) => DeviceTokenSync(ref),
);

/// Starts the heartbeat once FCM is up: register at launch, on every token
/// rotation ([tokenRefresh]) and on every store/language switch. Login and
/// logout are the auth controller's.
///
/// The launch registration waits for the HubApp probe when it hasn't answered
/// yet: it happens when the `push` switch turns out to be on.
void startDeviceTokenSync(
  ProviderContainer container, {
  required Stream<String> tokenRefresh,
}) {
  final sync = container.read(deviceTokenSyncProvider);
  if (!container.read(hubAppProvider).isLoading) unawaited(sync.register());
  tokenRefresh.listen((_) => unawaited(sync.register()));
  container.listen<String>(
    storeControllerProvider.select((s) => s.activeLocale),
    (previous, next) {
      if (previous != null && previous != next) unawaited(sync.register());
    },
  );
  container.listen<bool>(
    hubAppAccountFeaturesProvider.select((f) => f.pushDevices),
    (previous, next) {
      if (next && previous == false) unawaited(sync.register());
    },
  );
}
