import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../error/failure.dart';
import '../graphql/graphql_client.dart';
import '../storage/local_cache.dart';
import '../storage/locale_prefs.dart';
import '../storage/secure_token_store.dart';
import 'store_repository.dart';
import 'store_view.dart';

/// Immutable active-store state. [activeStoreCode] is what the GraphQL
/// `Store` header is set to on each request.
@immutable
class StoreState {
  const StoreState({
    required this.activeLocale,
    required this.localeToCode,
    required this.defaultLocale,
    required this.currency,
    this.stores = const <StoreView>[],
  });

  /// Active app language: `en` or `ar`.
  final String activeLocale;

  /// Resolved `language -> store_code` map (authoritative once stores load).
  final Map<String, String> localeToCode;

  final String defaultLocale;
  final String currency;
  final List<StoreView> stores;

  String get activeStoreCode =>
      localeToCode[activeLocale] ?? localeToCode[defaultLocale] ?? '';

  bool get isRtl => activeLocale == 'ar';
  Locale get locale => Locale(activeLocale);

  StoreState copyWith({
    String? activeLocale,
    Map<String, String>? localeToCode,
    String? defaultLocale,
    String? currency,
    List<StoreView>? stores,
  }) => StoreState(
    activeLocale: activeLocale ?? this.activeLocale,
    localeToCode: localeToCode ?? this.localeToCode,
    defaultLocale: defaultLocale ?? this.defaultLocale,
    currency: currency ?? this.currency,
    stores: stores ?? this.stores,
  );
}

/// Owns the active store view + locale. Resolves the real `locale -> store_code`
/// mapping from `availableStores` (bootstrapped with a default code), persists
/// the choice, and performs the **atomic switch** (persist → reset cache →
/// rebuild via state change).
class StoreController extends Notifier<StoreState> {
  @override
  StoreState build() {
    final config = ref.read(appConfigProvider);
    final persisted = ref.read(localePrefsProvider).read();
    final locale = persisted ?? config.defaultLocale;
    return StoreState(
      activeLocale: locale,
      localeToCode: config.provisionalStoreCodes,
      defaultLocale: config.defaultLocale,
      currency: config.currency,
    );
  }

  /// Loads store views: cache first (fast paint), then refreshes from the
  /// network and persists. Failures keep the provisional/cached mapping.
  ///
  /// Self-heal: a stale/expired token in secure storage makes Magento reject
  /// this very first request (`auth` — "Consumer key has expired"; or, for a
  /// malformed token, an edge `service` 403). Browsing needs no token (guest
  /// GraphQL returns 200), so on those failures we drop the token and retry
  /// once as guest, recovering in-session instead of failing every request.
  /// The `service` bucket also holds plain WAF/CloudFront error pages, which say
  /// nothing about the token — see [_healOrKeepToken] for how the two are told
  /// apart. A plain network blip keeps the provisional/cached mapping (the token
  /// may be perfectly valid — the device is just offline).
  Future<void> loadStores() {
    final pending = _load();
    _inFlight = pending;
    return pending;
  }

  /// The in-flight (or finished) [loadStores] call, so [ensureStoresLoaded]
  /// can join it instead of starting a second one.
  Future<void>? _inFlight;

  /// Awaits the initial store load, so callers that need [StoreState.stores]
  /// before the user has navigated anywhere don't race it.
  ///
  /// `bootstrap.dart` fires [loadStores] unawaited, and on a warm install the
  /// cached views land synchronously — but on a **fresh** install the list is
  /// still empty for the first frames. A deep link resolving in that window
  /// saw no store views, so it couldn't tell which language the incoming
  /// `/uae-ar/` path belonged to and resolved it against the default (English)
  /// store instead.
  ///
  /// Returns at once when the views are already there, joins the bootstrap call
  /// when one is in flight, and starts one otherwise. [timeout] bounds the wait
  /// so a dead network delays a deep link rather than wedging it; on timeout —
  /// or a failed load — the caller simply proceeds with whatever mapping the
  /// provisional/cached config gave it, exactly as before.
  Future<void> ensureStoresLoaded({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (state.stores.isNotEmpty) return;
    await (_inFlight ?? loadStores()).timeout(timeout, onTimeout: () {});
  }

  Future<void> _load() async {
    final cache = ref.read(localCacheProvider);
    final cached = cache.readStores();
    if (cached != null && cached.isNotEmpty) {
      _applyStores(cached.map(StoreView.fromJson).toList(growable: false));
    }
    try {
      await _fetchAndApplyStores(cache);
    } on Failure catch (failure) {
      await _healOrKeepToken(cache, failure);
    } on Object {
      // Non-fatal: provisional/cached mapping remains in effect.
    }
  }

  /// Decides what a failed bootstrap fetch means for the **stored customer
  /// token**. Getting this wrong signs people out, so each branch needs proof.
  ///
  /// `auth` — Magento explicitly rejected the bearer ("Consumer key has
  /// expired"). That *is* the proof: drop the token and retry as guest.
  ///
  /// `service` — a non-JSON body, which covers three very different things: an
  /// AWS WAF / CloudFront error page, a response the transport couldn't decode,
  /// or an edge 403 provoked by a malformed bearer (CLAUDE.md §7). Only the last
  /// is the token's fault, so **prove it** — re-run the query on the token-less
  /// client and clear the token only if that guest call succeeds where the
  /// authenticated one didn't. Clearing on every `service` failure (as this did)
  /// signed customers out on any transient edge hiccup at launch, and `_load`
  /// runs on every cold start — the CL042-DEV20 "logged out too soon" report.
  ///
  /// Anything else (network / offline) leaves both the token and the cached
  /// mapping alone: the device is down, the session is fine.
  Future<void> _healOrKeepToken(LocalCache cache, Failure failure) async {
    if (failure.kind == FailureKind.auth) {
      await _dropToken();
      try {
        await _fetchAndApplyStores(cache);
      } on Object {
        // Still down — provisional/cached mapping remains in effect.
      }
      return;
    }
    if (failure.kind != FailureKind.service) return;
    if (await ref.read(secureTokenStoreProvider).read() == null) return;

    final List<StoreView> stores;
    try {
      stores = await ref
          .read(guestStoreRepositoryProvider)
          .fetchAvailableStores();
    } on Object {
      // Guest failed too, so the bearer was never the problem. Keep the
      // customer signed in and fall back to the provisional/cached mapping.
      return;
    }
    await _dropToken();
    await _applyAndCache(stores, cache);
  }

  Future<void> _dropToken() async {
    await ref.read(secureTokenStoreProvider).clear();
    ref.invalidate(graphqlClientProvider);
  }

  Future<void> _fetchAndApplyStores(LocalCache cache) async {
    final stores = await ref
        .read(storeRepositoryProvider)
        .fetchAvailableStores();
    await _applyAndCache(stores, cache);
  }

  Future<void> _applyAndCache(List<StoreView> stores, LocalCache cache) async {
    if (stores.isEmpty) return;
    _applyStores(stores);
    await cache.writeStores(
      stores.map((s) => s.toJson()).toList(growable: false),
    );
  }

  void _applyStores(List<StoreView> stores) {
    final map = <String, String>{};
    String? defaultLocale;
    for (final store in stores) {
      if (store.languageCode.isEmpty || store.storeCode.isEmpty) continue;
      map[store.languageCode] = store.storeCode;
      if (store.isDefault) defaultLocale = store.languageCode;
    }
    final defaultStore = stores.firstWhere(
      (s) => s.isDefault,
      orElse: () => stores.first,
    );
    state = state.copyWith(
      stores: stores,
      localeToCode: map.isEmpty ? state.localeToCode : map,
      defaultLocale: defaultLocale ?? state.defaultLocale,
      currency: defaultStore.currency.isNotEmpty
          ? defaultStore.currency
          : state.currency,
    );
  }

  /// Atomic language/store switch: persist → reset GraphQL cache → state change
  /// (which rebuilds Directionality, router, and theme).
  Future<void> switchLocale(String locale) async {
    if (locale == state.activeLocale) return;
    await ref.read(localePrefsProvider).write(locale);
    state = state.copyWith(activeLocale: locale);
    // Recreate the client so its normalized cache is dropped and subsequent
    // queries refetch with the new `Store` header.
    ref.invalidate(graphqlClientProvider);
  }
}

final storeControllerProvider = NotifierProvider<StoreController, StoreState>(
  StoreController.new,
);
