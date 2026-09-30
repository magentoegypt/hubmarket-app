import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';
import '../../../../core/hubapp/hm_app_config.dart';
import '../../../../core/hubapp/hubapp_providers.dart';
import '../../../../core/network/platform_http_client.dart';
import '../../../../core/storage/local_cache.dart';
import '../../../../core/store/store_controller.dart';
import '../../../../core/store/store_urls.dart';
import 'algolia_settings.dart';

/// There is nothing to search Algolia with: not configured, the backend
/// settings couldn't be read, or the key is expired or refused. Search then
/// goes through GraphQL.
class AlgoliaUnavailable implements Exception {
  const AlgoliaUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'AlgoliaUnavailable($reason)';
}

/// The Hub Market App API's Algolia settings for a store view — the active
/// one's `hmAppConfig.algolia` — or null when that API isn't there. [fresh]
/// asks for the config to be read again first (the key was refused).
typedef HubAppAlgoliaSource =
    Future<HmAlgoliaConfig?> Function(String storeCode, {bool fresh});

/// Where the app gets its Algolia settings, per store view.
///
/// The storefront's key is an Algolia *secured* key restricted by
/// `validUntil` to 24 hours after it was issued, so the app can't ship one.
///
/// * With the Hub Market App API ([hubApp]), the key, its `valid_until`, the
///   index names and the search layout (facets with their store-view labels,
///   sort replicas, the query-suggestions index) come from
///   `hmAppConfig.algolia`, and no page is read. From a backend older than
///   the layout, it is read once from the storefront page below and kept for
///   [layoutMaxAge].
/// * Without it — today's fallback — everything is read the way the
///   website's own autocomplete reads it: from `window.algoliaConfig` on the
///   store view's home page, one GET of about 60 KB (gzip) that Magento's
///   full-page cache serves.
///
/// The result is kept in memory and in [LocalCache] until the key's
/// `validUntil`, so a restart doesn't fetch it again. A static
/// [AppConfig.algoliaSearchKey], when set, is used instead and nothing is
/// fetched.
class AlgoliaSettingsRepository {
  AlgoliaSettingsRepository({
    required this._config,
    required this._client,
    required this._cache,
    required this._storefrontPage,
    this._hubApp,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  final AppConfig _config;
  final http.Client _client;
  final LocalCache _cache;
  final Uri Function(String storeCode) _storefrontPage;
  final HubAppAlgoliaSource? _hubApp;
  final DateTime Function() _clock;
  final Duration timeout;

  /// How long a storefront facet/sort layout serves the Hub Market App key.
  static const Duration layoutMaxAge = Duration(days: 7);

  final Map<String, AlgoliaSettings> _memory = {};
  final Map<String, Future<AlgoliaSettings>> _pending = {};

  /// Keys Algolia refused, per store view: the Hub Market App API may keep
  /// serving one from the HTTP cache for up to an hour.
  final Map<String, String> _refused = {};

  static String _cacheKey(String storeCode) => 'algolia_settings_$storeCode';
  static String _layoutKey(String storeCode) => 'algolia_layout_$storeCode';

  /// The settings to search [storeCode]'s indices with. Throws
  /// [AlgoliaUnavailable] when there are none.
  Future<AlgoliaSettings> settingsFor(String storeCode) async {
    if (!_config.algoliaConfigured) {
      throw const AlgoliaUnavailable('not configured');
    }
    if (storeCode.isEmpty) throw const AlgoliaUnavailable('no store view');
    final now = _clock();

    if (_config.algoliaSearchKey.trim().isNotEmpty) {
      final settings = AlgoliaSettings.fromAppConfig(_config, storeCode);
      if (!settings.usableAt(now)) {
        throw const AlgoliaUnavailable('the configured key has expired');
      }
      return settings;
    }

    final remembered = _memory[storeCode];
    if (remembered != null && remembered.usableAt(now)) return remembered;

    final cached = _readCache(storeCode);
    if (cached != null && cached.usableAt(now)) {
      return _memory[storeCode] = cached;
    }

    // A block body: `=> _pending.remove(…)` would hand whenComplete the very
    // future it is completing, and it would wait on itself forever.
    return _pending[storeCode] ??= _fetch(storeCode).whenComplete(() {
      _pending.remove(storeCode);
    });
  }

  /// Forgets [storeCode]'s settings — Algolia refused their key — so the next
  /// [settingsFor] reads fresh ones.
  Future<void> invalidate(String storeCode) async {
    final refused = _memory.remove(storeCode) ?? _readCache(storeCode);
    if (refused != null) _refused[storeCode] = refused.searchKey;
    try {
      await _cache.deleteKey(_cacheKey(storeCode));
    } on Object {
      // A cache that can't be written only costs a refetch.
    }
  }

  Future<AlgoliaSettings> _fetch(String storeCode) async {
    final fromHubApp = await _fromHubApp(storeCode);
    if (fromHubApp != null) return _remember(storeCode, fromHubApp);

    final settings = await _readStorefront(storeCode);
    if (!settings.usableAt(_clock())) {
      // The page came from a full-page cache older than its key.
      throw const AlgoliaUnavailable('the storefront key has expired');
    }
    return _remember(storeCode, settings);
  }

  /// Settings built on `hmAppConfig.algolia`, or null when the Hub Market App
  /// API has none (not deployed, no Algolia, or only a refused/expired key).
  Future<AlgoliaSettings?> _fromHubApp(String storeCode) async {
    final source = _hubApp;
    if (source == null) return null;
    final refused = _refused[storeCode];
    HmAlgoliaConfig? hub;
    try {
      hub = await source(storeCode, fresh: refused != null);
    } on Object {
      return null;
    }
    if (hub == null || hub.searchApiKey == refused) return null;

    // The backend serves the layout itself: no storefront page to read.
    var layout = hub.layout != null ? null : _readLayout(storeCode);
    if (hub.layout == null && layout == null) {
      try {
        layout = await _readStorefront(storeCode);
      } on AlgoliaUnavailable {
        // Search still works on the basic facets; the layout is read again
        // next time.
      }
    }
    final settings = AlgoliaSettings.fromHubApp(
      hub,
      config: _config,
      storeCode: storeCode,
      layout: layout,
    );
    return settings.usableAt(_clock()) ? settings : null;
  }

  Future<AlgoliaSettings> _remember(
    String storeCode,
    AlgoliaSettings settings,
  ) async {
    _memory[storeCode] = settings;
    _refused.remove(storeCode);
    try {
      await _cache.writeString(
        _cacheKey(storeCode),
        jsonEncode(settings.toStorefrontConfig()),
      );
    } on Object {
      // Not persisted: the next launch reads the settings again.
    }
    return settings;
  }

  /// `window.algoliaConfig` of [storeCode]'s storefront page, whatever the age
  /// of its key; its facet/sort layout is kept for [layoutMaxAge].
  Future<AlgoliaSettings> _readStorefront(String storeCode) async {
    final uri = _storefrontPage(storeCode);
    final http.Response response;
    try {
      response = await _client
          .get(
            uri,
            headers: {'Accept': 'text/html', 'User-Agent': _config.userAgent},
          )
          .timeout(timeout);
    } on Object catch (error) {
      throw AlgoliaUnavailable('storefront page: ${error.runtimeType}');
    }
    if (response.statusCode != 200) {
      throw AlgoliaUnavailable('storefront page: HTTP ${response.statusCode}');
    }

    final config = algoliaConfigFromHtml(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (config == null) {
      throw const AlgoliaUnavailable('storefront page has no algoliaConfig');
    }
    final AlgoliaSettings settings;
    try {
      settings = AlgoliaSettings.fromStorefrontConfig(config);
    } on FormatException catch (error) {
      throw AlgoliaUnavailable('algoliaConfig: ${error.message}');
    }
    try {
      await _cache.writeString(
        _layoutKey(storeCode),
        jsonEncode({
          'at': _clock().millisecondsSinceEpoch,
          'config': settings.toStorefrontConfig(),
        }),
      );
    } on Object {
      // Not persisted: the layout is read again next time.
    }
    return settings;
  }

  /// The storefront layout kept by [_readStorefront], unless older than
  /// [layoutMaxAge].
  AlgoliaSettings? _readLayout(String storeCode) {
    try {
      final raw = _cache.readString(_layoutKey(storeCode));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final at = decoded['at'];
      final config = decoded['config'];
      if (at is! int || config is! Map<String, dynamic>) return null;
      final age = _clock().difference(DateTime.fromMillisecondsSinceEpoch(at));
      if (age > layoutMaxAge) return null;
      return AlgoliaSettings.fromStorefrontConfig(config);
    } on Object {
      return null;
    }
  }

  AlgoliaSettings? _readCache(String storeCode) {
    try {
      final raw = _cache.readString(_cacheKey(storeCode));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? AlgoliaSettings.fromStorefrontConfig(decoded)
          : null;
    } on Object {
      return null;
    }
  }
}

/// The home page of store view [storeCode] — where the storefront renders
/// `window.algoliaConfig`: the view's `base_link_url` once store views have
/// loaded, else `/<store code>/` on the GraphQL endpoint's host (Hub Market's
/// store segments are its codes).
Uri storefrontHomeUri(StoreState state, AppConfig config, String storeCode) {
  if (state.activeStoreCode == storeCode) {
    final base = storeBaseUrl(state);
    if (base.isNotEmpty) return Uri.parse(base);
  }
  final endpoint = Uri.parse(config.graphqlEndpoint);
  final segments = endpoint.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isNotEmpty && segments.last == 'graphql') segments.removeLast();
  return Uri(
    scheme: endpoint.scheme,
    host: endpoint.host,
    port: endpoint.hasPort ? endpoint.port : null,
    pathSegments: [...segments, storeCode, ''],
  );
}

/// The HTTP client for Algolia and the storefront page. Tests swap in a fake.
final algoliaHttpClientProvider = Provider<http.Client>((ref) {
  final client = platformHttpClient(ref.watch(appConfigProvider).userAgent);
  ref.onDispose(client.close);
  return client;
});

/// Kept for the app's lifetime: it holds the settings until their key expires.
final algoliaSettingsRepositoryProvider = Provider<AlgoliaSettingsRepository>((
  ref,
) {
  final config = ref.watch(appConfigProvider);
  return AlgoliaSettingsRepository(
    config: config,
    client: ref.watch(algoliaHttpClientProvider),
    cache: ref.watch(localCacheProvider),
    // Read at call time: the store view follows the app language.
    storefrontPage: (storeCode) =>
        storefrontHomeUri(ref.read(storeControllerProvider), config, storeCode),
    hubApp: (storeCode, {bool fresh = false}) async {
      final hubApp = ref.read(hubAppProvider.notifier);
      if (fresh) await hubApp.refresh();
      return hubApp.algoliaFor(storeCode);
    },
  );
});
