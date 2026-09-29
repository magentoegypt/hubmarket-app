import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hubmarket_app/core/error/failure.dart';
import 'package:hubmarket_app/core/storage/local_cache.dart';
import 'package:hubmarket_app/core/storage/locale_prefs.dart';
import 'package:hubmarket_app/core/storage/secure_token_store.dart';
import 'package:hubmarket_app/core/store/store_controller.dart';
import 'package:hubmarket_app/core/store/store_repository.dart';
import 'package:hubmarket_app/core/store/store_view.dart';

import '../../support/fakes.dart';

/// Never answers, so a caller that awaits the load must fall back on a timeout.
class _HangingRepository implements StoreRepository {
  @override
  Future<List<StoreView>> fetchAvailableStores() => Completer<List<StoreView>>()
      .future;
}

/// Counts `availableStores` calls, to prove the load isn't started twice.
class _CountingRepository implements StoreRepository {
  _CountingRepository(this.stores);
  final List<StoreView> stores;
  int calls = 0;

  @override
  Future<List<StoreView>> fetchAvailableStores() async {
    calls++;
    return stores;
  }
}

/// Fails the first `availableStores` (as a stale token would), then succeeds.
class _AuthThenOkRepository implements StoreRepository {
  _AuthThenOkRepository(this.stores);
  final List<StoreView> stores;
  int calls = 0;

  @override
  Future<List<StoreView>> fetchAvailableStores() async {
    calls++;
    if (calls == 1) throw const Failure(FailureKind.auth);
    return stores;
  }
}

/// Always fails with the `service` kind — the non-JSON bucket, which holds both
/// "the edge served a WAF/CloudFront HTML page" and "the bearer is malformed".
/// On its own it says nothing about whether the token is any good.
class _ServiceFailureRepository implements StoreRepository {
  int calls = 0;

  @override
  Future<List<StoreView>> fetchAvailableStores() async {
    calls++;
    throw const Failure(FailureKind.service);
  }
}

ProviderContainer _serviceFailureContainer({
  required StoreRepository guest,
  required SecureTokenStore tokenStore,
  required StoreRepository authed,
}) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(null)),
      storeRepositoryProvider.overrideWithValue(authed),
      guestStoreRepositoryProvider.overrideWithValue(guest),
      secureTokenStoreProvider.overrideWithValue(tokenStore),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

ProviderContainer _container({String? persistedLocale}) {
  final container = ProviderContainer(
    overrides: [
      localCacheProvider.overrideWithValue(FakeLocalCache()),
      localePrefsProvider.overrideWithValue(FakeLocalePrefs(persistedLocale)),
      storeRepositoryProvider.overrideWithValue(
        FakeStoreRepository(kSampleStores),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('StoreController', () {
    test('seeds provisional mapping and default locale before loading', () {
      final container = _container();
      final state = container.read(storeControllerProvider);
      expect(state.activeLocale, 'en');
      expect(state.localeToCode, {'en': 'en', 'ar': 'ar'});
      expect(state.activeStoreCode, 'en');
    });

    test('honours the persisted locale', () {
      final container = _container(persistedLocale: 'ar');
      final state = container.read(storeControllerProvider);
      expect(state.activeLocale, 'ar');
      expect(state.isRtl, isTrue);
      expect(state.activeStoreCode, 'ar');
    });

    test(
      'resolves locale->code, default view and currency from availableStores',
      () async {
        final container = _container();
        await container.read(storeControllerProvider.notifier).loadStores();
        final state = container.read(storeControllerProvider);

        expect(state.stores, hasLength(2));
        expect(state.localeToCode['en'], 'eg_en');
        expect(state.localeToCode['ar'], 'eg_ar');
        expect(state.defaultLocale, 'en');
        expect(state.currency, 'AED');
      },
    );

    test('switchLocale flips the active store code', () async {
      final container = _container();
      await container.read(storeControllerProvider.notifier).loadStores();

      await container.read(storeControllerProvider.notifier).switchLocale('ar');
      final state = container.read(storeControllerProvider);

      expect(state.activeLocale, 'ar');
      expect(state.isRtl, isTrue);
      expect(state.activeStoreCode, 'eg_ar');
    });

    test('loadStores self-heals a stale token: clears it and retries as guest',
        () async {
      final tokenStore = FakeSecureTokenStore('stale-token');
      final repo = _AuthThenOkRepository(kSampleStores);
      final container = ProviderContainer(
        overrides: [
          localCacheProvider.overrideWithValue(FakeLocalCache()),
          localePrefsProvider.overrideWithValue(FakeLocalePrefs(null)),
          storeRepositoryProvider.overrideWithValue(repo),
          secureTokenStoreProvider.overrideWithValue(tokenStore),
        ],
      );
      addTearDown(container.dispose);

      await container.read(storeControllerProvider.notifier).loadStores();

      expect(repo.calls, 2, reason: 'retried once as guest after the auth fail');
      expect(await tokenStore.read(), isNull, reason: 'stale token was wiped');
      expect(container.read(storeControllerProvider).stores, hasLength(2));
    });

    // CL042-DEV20. `_load` runs on every cold start, and a `service` failure is
    // usually the edge misbehaving — not a bad token. Wiping the token on sight
    // signed customers out for no reason, which read to them as "the login
    // expires way too fast". Only a guest retry can tell the two apart.
    group('service failure at bootstrap', () {
      test('keeps the token when the guest retry fails too', () async {
        final tokenStore = FakeSecureTokenStore('good-token');
        final guest = _ServiceFailureRepository();
        final container = _serviceFailureContainer(
          guest: guest,
          tokenStore: tokenStore,
          authed: _ServiceFailureRepository(),
        );

        await container.read(storeControllerProvider.notifier).loadStores();

        expect(guest.calls, 1, reason: 'probed before touching the token');
        expect(
          await tokenStore.read(),
          'good-token',
          reason: 'the edge was down, not the session',
        );
        expect(container.read(storeControllerProvider).stores, isEmpty);
      });

      test('clears the token when the guest retry succeeds', () async {
        final tokenStore = FakeSecureTokenStore('malformed-token');
        final guest = _CountingRepository(kSampleStores);
        final container = _serviceFailureContainer(
          guest: guest,
          tokenStore: tokenStore,
          authed: _ServiceFailureRepository(),
        );

        await container.read(storeControllerProvider.notifier).loadStores();

        expect(guest.calls, 1);
        expect(
          await tokenStore.read(),
          isNull,
          reason: 'guest worked where the bearer did not — the token is at fault',
        );
        expect(
          container.read(storeControllerProvider).stores,
          hasLength(2),
          reason: 'the guest response still bootstraps the store views',
        );
      });

      test('never probes when there is no token to blame', () async {
        final guest = _CountingRepository(kSampleStores);
        final container = _serviceFailureContainer(
          guest: guest,
          tokenStore: FakeSecureTokenStore(),
          authed: _ServiceFailureRepository(),
        );

        await container.read(storeControllerProvider.notifier).loadStores();

        expect(guest.calls, 0);
      });
    });

    // The cold-start gap: `bootstrap` fires loadStores unawaited, so on a fresh
    // install the view list is empty for the first frames and anything reading
    // it (a deep link) saw nothing.
    group('ensureStoresLoaded', () {
      ProviderContainer containerWith(StoreRepository repo) {
        final container = ProviderContainer(
          overrides: [
            localCacheProvider.overrideWithValue(FakeLocalCache()),
            localePrefsProvider.overrideWithValue(FakeLocalePrefs(null)),
            storeRepositoryProvider.overrideWithValue(repo),
            secureTokenStoreProvider.overrideWithValue(FakeSecureTokenStore()),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      test('loads the views when nothing has loaded them yet', () async {
        final container = containerWith(FakeStoreRepository(kSampleStores));
        expect(container.read(storeControllerProvider).stores, isEmpty);

        await container.read(storeControllerProvider.notifier)
            .ensureStoresLoaded();

        expect(container.read(storeControllerProvider).stores, hasLength(2));
      });

      test('joins the bootstrap call instead of starting a second one',
          () async {
        final repo = _CountingRepository(kSampleStores);
        final container = containerWith(repo);
        final notifier = container.read(storeControllerProvider.notifier);

        final bootstrap = notifier.loadStores();
        await Future.wait([bootstrap, notifier.ensureStoresLoaded()]);

        expect(repo.calls, 1);
        expect(container.read(storeControllerProvider).stores, hasLength(2));
      });

      test('returns at once when the views are already there', () async {
        final repo = _CountingRepository(kSampleStores);
        final container = containerWith(repo);
        final notifier = container.read(storeControllerProvider.notifier);
        await notifier.loadStores();

        await notifier.ensureStoresLoaded();

        expect(repo.calls, 1, reason: 'no second fetch once loaded');
      });

      test('gives up on timeout rather than wedging the caller', () async {
        final container = containerWith(_HangingRepository());

        await container
            .read(storeControllerProvider.notifier)
            .ensureStoresLoaded(timeout: const Duration(milliseconds: 20));

        // Falls through to the provisional mapping instead of hanging forever.
        expect(container.read(storeControllerProvider).stores, isEmpty);
      });
    });
  });
}
