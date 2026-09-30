import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/connectivity.dart';
import '../store/store_controller.dart';
import 'hm_app_config.dart';
import 'hubapp_config_repository.dart';
import 'hubapp_models.dart';
import 'hubapp_query.dart';

/// Whether the server has the Hub Market App (`MagentoEgypt_HubApp`) API.
enum HubAppStatus {
  /// Not known (yet): the probe is running, or it failed for a reason that
  /// says nothing about the module (offline, timeout, 5xx). Behave as Build 1
  /// and let the next probe decide — never read this as "not deployed".
  unknown,

  /// `hmAppConfig` answered: the Build 2 features may run.
  available,

  /// The server said it has no `hmAppConfig` ("Cannot query field"): the
  /// module isn't deployed there. Build 1 until the next launch or store
  /// switch.
  unavailable,
}

/// What the last probe found, with the settings it read.
@immutable
class HubAppState {
  const HubAppState.available(HmAppConfig this.config)
    : status = HubAppStatus.available,
      error = null;

  const HubAppState.unavailable([this.error])
    : status = HubAppStatus.unavailable,
      config = null;

  const HubAppState.unknown([this.error])
    : status = HubAppStatus.unknown,
      config = null;

  final HubAppStatus status;

  /// Non-null exactly when [isAvailable].
  final HmAppConfig? config;

  /// Why the probe didn't find the module — diagnostics only.
  final Object? error;

  bool get isAvailable => status == HubAppStatus.available;

  @override
  String toString() => 'HubAppState(${status.name}${error == null ? '' : ', $error'})';
}

/// Probes `hmAppConfig` once per launch and per store switch, and holds the
/// settings it read.
///
/// * [HubAppMissing] (the server has no such field) → [HubAppStatus.unavailable];
/// * any other failure → [HubAppStatus.unknown], never latched: the probe runs
///   again on its own ([autoRetries] times, [autoRetryDelay] apart: the first
///   call after a deploy or an idle spell can take 15-25 s while the server's
///   caches rebuild, past the probe's timeout, and by the retry it is warm),
///   when the device comes back online, when the app returns to the foreground
///   ([onResume]) and when a screen retries ([refresh]).
///
/// Features read [hubAppStatusProvider] / [hmAppConfigProvider] /
/// [hubAppFlagProvider]; the Home reads this provider itself to tell "still
/// checking" (loading) from "couldn't tell" (unknown).
class HubAppController extends AsyncNotifier<HubAppState> {
  DateTime? _checkedAt;

  /// A config older than this is re-read when the app returns to the
  /// foreground (maintenance, force-update, flags and the Algolia key change
  /// server-side; the GET is served from the HTTP cache anyway).
  static const Duration staleAfter = Duration(hours: 1);

  /// How many times an unknown probe is retried without anyone asking, and how
  /// long it waits before each retry.
  static const int autoRetries = 2;
  static const Duration autoRetryDelay = Duration(seconds: 5);

  int _autoRetried = 0;

  @override
  Future<HubAppState> build() {
    _autoRetried = 0;
    ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
    ref.listen<bool>(isOfflineProvider, (wasOffline, offline) {
      if (wasOffline == true && !offline) unawaited(retryIfUnknown());
    });
    return _probe();
  }

  Future<HubAppState> _probe() async {
    final repository = ref.read(hubAppConfigRepositoryProvider);
    try {
      final config = await repository.fetch(platform: HmPlatform.current);
      _checkedAt = DateTime.now();
      _autoRetried = 0;
      return HubAppState.available(config);
    } on HubAppMissing catch (error) {
      _checkedAt = DateTime.now();
      _autoRetried = 0;
      return HubAppState.unavailable(error);
    } on Object catch (error) {
      _scheduleAutoRetry();
      return HubAppState.unknown(error);
    }
  }

  /// One more probe in [autoRetryDelay], while [autoRetries] allow it.
  void _scheduleAutoRetry() {
    if (_autoRetried >= autoRetries) return;
    _autoRetried++;
    final timer = Timer(autoRetryDelay, () => unawaited(retryIfUnknown()));
    ref.onDispose(timer.cancel);
  }

  /// Probes again, keeping the current state visible meanwhile.
  Future<void> refresh() async {
    state = const AsyncLoading<HubAppState>().copyWithPrevious(state);
    final next = await _probe();
    state = AsyncData(next);
  }

  /// Probes again only when the last probe couldn't tell.
  Future<void> retryIfUnknown() async {
    final current = state;
    if (current.isLoading) return;
    if (current.valueOrNull?.status != HubAppStatus.unknown) return;
    await refresh();
  }

  /// The app came back to the foreground: settle an unknown status, and
  /// re-read a config older than [staleAfter].
  Future<void> onResume() async {
    final current = state.valueOrNull;
    if (state.isLoading || current == null) return;
    final checkedAt = _checkedAt;
    final stale =
        checkedAt == null || DateTime.now().difference(checkedAt) > staleAfter;
    if (current.status == HubAppStatus.unknown ||
        (current.status == HubAppStatus.available && stale)) {
      await refresh();
    }
  }

  /// The Algolia settings of [storeCode] from `hmAppConfig`, re-reading the
  /// config once when its key is about to expire; null when HubApp is not
  /// available, has no Algolia for that store view, or only an expired key.
  Future<HmAlgoliaConfig?> algoliaFor(String storeCode) async {
    HmAlgoliaConfig? pick(HubAppState? s) {
      final config = s?.config;
      if (config == null || config.storeCode != storeCode) return null;
      return config.algolia;
    }

    HubAppState? current;
    try {
      current = await future;
    } on Object {
      return null;
    }
    var algolia = pick(current);
    if (algolia == null) return null;
    if (!_keyUsable(algolia)) {
      await refresh();
      algolia = pick(state.valueOrNull);
      if (algolia == null || !_keyUsable(algolia)) return null;
    }
    return algolia;
  }

  static bool _keyUsable(HmAlgoliaConfig algolia) {
    final until = algolia.validUntil;
    return until == null ||
        DateTime.now().isBefore(until.subtract(const Duration(minutes: 5)));
  }
}

/// The probe and the settings it read — see [HubAppController].
final hubAppProvider = AsyncNotifierProvider<HubAppController, HubAppState>(
  HubAppController.new,
);

/// Whether the Hub Market App API is there: gate Build 2 features on
/// [HubAppStatus.available] and keep the Build 1 behaviour otherwise
/// ([HubAppStatus.unknown] while probing or after a network failure).
final hubAppStatusProvider = Provider<HubAppStatus>(
  (ref) => ref.watch(hubAppProvider).valueOrNull?.status ?? HubAppStatus.unknown,
);

/// The active store view's `hmAppConfig`; null unless HubApp is available.
final hmAppConfigProvider = Provider<HmAppConfig?>(
  (ref) => ref.watch(hubAppProvider).valueOrNull?.config,
);

/// Whether the server runs the HubApp satellite [code] ([HubAppCapability]):
/// HubApp is available and `hmAppConfig.capabilities` lists it. False while
/// probing, without HubApp, and on a server from before the list.
final hubAppCapabilityProvider = Provider.family<bool, String>(
  (ref, code) => ref.watch(hmAppConfigProvider)?.hasCapability(code) ?? false,
);

/// A remote feature switch (`store_credit`, `returns`, `whatsapp_login`,
/// `push`, …): null when HubApp isn't available or the backend doesn't list
/// the code — each feature decides its own default (`?? false` for "off
/// unless switched on").
final hubAppFlagProvider = Provider.family<bool?, String>(
  (ref, code) => ref.watch(hmAppConfigProvider)?.flag(code),
);
