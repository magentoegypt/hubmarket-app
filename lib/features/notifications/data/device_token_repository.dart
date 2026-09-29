import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/app_info.dart';
import '../../../core/graphql/graphql_client.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/storage/local_cache.dart';

/// Registers/removes this device's FCM token with Magento (the
/// `MagentoEgypt_NotificationGraphQl` module — see
/// `docs/backend/notifications-contract.md`). Token-targeting is what lets the
/// backend push order/welcome/reset notifications to a specific customer.
///
/// **Degrades gracefully:** every call is a no-op when FCM is unavailable (no
/// token), and any GraphQL error (e.g. the backend mutations aren't deployed
/// yet) is swallowed — registration must never surface to the user or block
/// login/logout. Mirrors the "degrade until deployed" pattern used for payments.
class DeviceTokenRepository {
  DeviceTokenRepository(this._client);

  final GraphQLClient _client;

  static const String _registerDoc = r'''
mutation RegisterDeviceToken($input: DeviceTokenInput!) {
  registerDeviceToken(input: $input) { success }
}''';

  static const String _removeDoc = r'''
mutation RemoveDeviceToken($token: String!) {
  removeDeviceToken(token: $token) { success }
}''';

  Future<void> register({
    required String token,
    required String platform,
    String? appVersion,
  }) => _run(_registerDoc, {
    'input': {
      'token': token,
      'platform': platform,
      if (appVersion != null) 'app_version': appVersion,
    },
  });

  Future<void> remove(String token) => _run(_removeDoc, {'token': token});

  Future<void> _run(String document, Map<String, dynamic> variables) async {
    try {
      final result = await _client.mutate(
        MutationOptions(
          document: gql(document),
          variables: variables,
          fetchPolicy: FetchPolicy.networkOnly,
        ),
      );
      if (result.hasException) {
        debugPrint('DeviceToken: mutation failed (backend not ready?) — '
            '${result.exception}');
      }
    } catch (error) {
      debugPrint('DeviceToken: $error');
    }
  }
}

final deviceTokenRepositoryProvider = Provider<DeviceTokenRepository>(
  (ref) => DeviceTokenRepository(ref.watch(graphqlClientProvider)),
);

/// Orchestrates *when* the device token is (re)registered: app launch + token
/// refresh (wired in `bootstrap`), login (re-binds the guest token to the
/// customer), store/language switch (refreshes the locale), and logout (removes
/// it while the bearer is still valid). The `Store` header + bearer are applied
/// automatically by the GraphQL link chain, so a single `register()` call
/// always reflects the current locale/auth state.
class DeviceTokenSync {
  DeviceTokenSync(this._ref);

  final Ref _ref;

  String get _platform =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  /// Register the current FCM token (no-op when FCM is off / token is null, or
  /// when the user has turned push OFF). The opt-out check makes the launch /
  /// login / token-refresh heartbeat respect the Edit Profile / Settings toggle
  /// — otherwise it would silently re-add a token the user removed.
  Future<void> register() async {
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
  /// the resolver can scope the delete to the authenticated customer.
  Future<void> unregister() async {
    final token = await NotificationService.instance.token();
    if (token == null || token.isEmpty) return;
    await _ref.read(deviceTokenRepositoryProvider).remove(token);
  }
}

final deviceTokenSyncProvider = Provider<DeviceTokenSync>(
  (ref) => DeviceTokenSync(ref),
);
