import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/app_info.dart';
import 'package:hubmarket_app/core/config/hubapp_account.dart';
import 'package:hubmarket_app/core/graphql/graphql_client.dart';
import 'package:hubmarket_app/core/hubapp/hubapp.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/features/auth/data/auth_repository.dart';
import 'package:hubmarket_app/features/auth/presentation/auth_controller.dart';
import 'package:hubmarket_app/features/notifications/data/device_token_repository.dart';
import 'package:hubmarket_app/features/notifications/presentation/notification_settings_controller.dart';

import '../../support/fakes.dart';
import '../../support/hubapp_fakes.dart';
import '../../support/store_credit_fakes.dart';

/// Records, in one log shared with the auth repository, every device call
/// and whether a customer bearer was stored when it went out.
class _Devices implements DeviceTokenRepository {
  _Devices(this.log, this.tokens);

  final List<String> log;
  final SecureTokenStore tokens;
  bool missing = false;

  Future<void> _record(String call) async {
    log.add('$call:${await tokens.read() ?? 'guest'}');
    if (missing) {
      throw const HubAppMissing(
        'Cannot query field "hmRegisterDevice" on type "Mutation".',
      );
    }
  }

  @override
  Future<bool> register({
    required String token,
    required HmPlatform platform,
    String? appVersion,
  }) async {
    await _record('register:$token:${platform.wire}:$appVersion');
    return true;
  }

  @override
  Future<bool> remove(String token) async {
    await _record('unregister:$token');
    return true;
  }
}

class _Auth extends FakeAuthRepository {
  _Auth(this.log);

  final List<String> log;

  @override
  Future<void> revokeToken() async => log.add('revokeToken');

  @override
  Future<void> deleteAccount() async {
    log.add('deleteCustomer');
    await super.deleteAccount();
  }
}

/// A probe a test can settle later, the way the real one answers after
/// launch.
class _LateHubApp extends FakeHubAppController {
  _LateHubApp() : super(const HubAppState.unknown());

  void settle(HubAppState next) => state = AsyncData(next);
}

class _Harness {
  _Harness({
    bool fcm = true,
    bool push = true,
    bool deployed = true,
    String? bearer,
    Override? hubApp,
  }) : tokens = FakeSecureTokenStore(bearer) {
    devices = _Devices(log, tokens);
    container = ProviderContainer(
      overrides: [
        secureTokenStoreProvider.overrideWithValue(tokens),
        authRepositoryProvider.overrideWithValue(_Auth(log)),
        deviceTokenRepositoryProvider.overrideWithValue(devices),
        pushNotificationsAvailableProvider.overrideWithValue(fcm),
        hubApp ??
            accountHubApp(deployed: deployed, storeCredit: false, push: push),
        fcmTokenProvider.overrideWithValue(() async => 'fcm-1'),
        devicePlatformProvider.overrideWithValue(HmPlatform.android),
        appSemverProvider.overrideWith((ref) async => '1.0.0'),
        localCacheProvider.overrideWithValue(cache),
        localePrefsProvider.overrideWithValue(FakeLocalePrefs('en')),
        storeRepositoryProvider.overrideWithValue(
          FakeStoreRepository(kSampleStores),
        ),
        graphqlClientProvider.overrideWithValue(fakeGraphQLClient()),
      ],
    );
    addTearDown(container.dispose);
  }

  final List<String> log = [];
  final FakeSecureTokenStore tokens;
  final FakeLocalCache cache = FakeLocalCache();
  late final _Devices devices;
  late final ProviderContainer container;

  DeviceTokenSync get sync => container.read(deviceTokenSyncProvider);
  AuthController get auth => container.read(authControllerProvider.notifier);

  /// Lets the auth controller restore the stored session.
  Future<void> settleSession() async {
    container.read(authControllerProvider);
    await pumpEventQueue();
  }
}

void main() {
  group('DeviceTokenSync', () {
    test(
      'registers the FCM token with the platform and the app version',
      () async {
        final h = _Harness();
        await h.sync.register();
        expect(h.log, ['register:fcm-1:ANDROID:1.0.0:guest']);
      },
    );

    test(
      'FCM off: nothing is sent, and the backend is not even asked',
      () async {
        final h = _Harness(
          fcm: false,
          hubApp: hubAppAccountFeaturesProvider.overrideWith(
            (ref) => throw StateError('asked the backend'),
          ),
        );
        await h.sync.register();
        await h.sync.unregister();
        expect(h.log, isEmpty);
      },
    );

    test('nothing is sent while the push switch is off', () async {
      final h = _Harness(push: false);
      await h.sync.register();
      await h.sync.unregister();
      expect(h.log, isEmpty);
    });

    test('Build 1: nothing is sent to a server without HubApp', () async {
      final h = _Harness(deployed: false);
      await h.sync.register();
      expect(h.log, isEmpty);
    });

    test(
      'a push opt-out keeps the heartbeat from re-adding the device',
      () async {
        final h = _Harness();
        await h.cache.writeString(kPromoPrefKey, 'false');
        await h.sync.register();
        expect(h.log, isEmpty);
      },
    );

    test('a server lacking the account module is asked once', () async {
      final h = _Harness()..devices.missing = true;
      await h.sync.register();
      await h.sync.register();
      await h.sync.unregister();
      expect(h.log, ['register:fcm-1:ANDROID:1.0.0:guest']);
      expect(
        h.container.read(hubAppAccountFeaturesProvider),
        HubAppAccountFeatures.none,
      );
    });
  });

  group('call sequence', () {
    test('login re-binds the device to the customer', () async {
      final h = _Harness();
      await h.settleSession();
      await h.auth.login('layla@example.com', 'password1');
      await pumpEventQueue();
      expect(h.log, ['register:fcm-1:ANDROID:1.0.0:fake-token']);
    });

    test(
      'logout switches the device off with the bearer, then revokes it',
      () async {
        final h = _Harness(bearer: 'customer-token');
        await h.settleSession();
        await h.auth.logout();
        expect(h.log, ['unregister:fcm-1:customer-token', 'revokeToken']);
        expect(await h.tokens.read(), isNull);
      },
    );

    test('account deletion switches the device off first', () async {
      final h = _Harness(bearer: 'customer-token');
      await h.settleSession();
      await h.auth.deleteAccount();
      expect(h.log, ['unregister:fcm-1:customer-token', 'deleteCustomer']);
    });

    test('launch, token refresh and a store switch register again', () async {
      final h = _Harness();
      final refresh = StreamController<String>();
      addTearDown(refresh.close);
      startDeviceTokenSync(h.container, tokenRefresh: refresh.stream);
      await pumpEventQueue();
      expect(h.log, ['register:fcm-1:ANDROID:1.0.0:guest']);

      refresh.add('fcm-2');
      await pumpEventQueue();
      expect(h.log, hasLength(2));

      await h.container
          .read(storeControllerProvider.notifier)
          .switchLocale('ar');
      await pumpEventQueue();
      expect(h.log, hasLength(3));
      expect(h.log.toSet(), {'register:fcm-1:ANDROID:1.0.0:guest'});
    });

    test(
      'registers once the probe finds the push switch on after launch',
      () async {
        final probe = _LateHubApp();
        final h = _Harness(hubApp: hubAppProvider.overrideWith(() => probe));
        startDeviceTokenSync(h.container, tokenRefresh: const Stream.empty());
        await pumpEventQueue();
        expect(h.log, isEmpty);

        probe.settle(HubAppState.available(hubAppAccountConfig(push: true)));
        await pumpEventQueue();
        expect(h.log, ['register:fcm-1:ANDROID:1.0.0:guest']);
      },
    );

    test(
      'opting out of push switches the device off; opting in adds it back',
      () async {
        final h = _Harness();
        final settings = h.container.read(
          notificationSettingsProvider.notifier,
        );
        await settings.setPromotions(false);
        await settings.setPromotions(true);
        expect(h.log, [
          'unregister:fcm-1:guest',
          'register:fcm-1:ANDROID:1.0.0:guest',
        ]);
      },
    );
  });

  group('DeviceTokenRepository', () {
    test('registers through the platform document, token and version as '
        'variables', () async {
      final client = fakeHubAppClient({
        'HmRegisterDeviceAndroid': {
          'hmRegisterDevice': {'__typename': 'HmDeviceOutput', 'success': true},
        },
        'HmRegisterDeviceIos': {
          'hmRegisterDevice': {'__typename': 'HmDeviceOutput', 'success': true},
        },
      });
      final repo = DeviceTokenRepository(client);
      expect(
        await repo.register(
          token: 'fcm-1',
          platform: HmPlatform.android,
          appVersion: '1.0.0',
        ),
        isTrue,
      );
      await repo.register(token: 'fcm-1', platform: HmPlatform.ios);
      expect(client.requests.map(operationNameOf), [
        'HmRegisterDeviceAndroid',
        'HmRegisterDeviceIos',
      ]);
      expect(client.requests.first.variables, {
        'token': 'fcm-1',
        'appVersion': '1.0.0',
      });
    });

    test('unregisters by token', () async {
      final client = fakeHubAppClient({
        'HmUnregisterDevice': {
          'hmUnregisterDevice': {
            '__typename': 'HmDeviceOutput',
            'success': true,
          },
        },
      });
      expect(await DeviceTokenRepository(client).remove('fcm-1'), isTrue);
      expect(client.requests.single.variables, {'token': 'fcm-1'});
    });

    test('a server without the module throws HubAppMissing', () async {
      final client = fakeHubAppClient({
        'HmRegisterDeviceAndroid': hubAppMissingResponse(
          'hmRegisterDevice',
          type: 'Mutation',
        ),
      });
      await expectLater(
        DeviceTokenRepository(
          client,
        ).register(token: 'fcm-1', platform: HmPlatform.android),
        throwsA(isA<HubAppMissing>()),
      );
    });

    test('no document declares a variable of an Hm* type', () {
      for (final document in [
        DeviceTokenQueries.registerAndroid,
        DeviceTokenQueries.registerIos,
        DeviceTokenQueries.unregister,
      ]) {
        expect(document, isNot(matches(RegExp(r'\$\w+\s*:\s*\[?Hm'))));
      }
    });
  });
}
