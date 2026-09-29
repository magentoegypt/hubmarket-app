import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/app_config.dart';
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

/// Where the app gets its Algolia settings, per store view.
///
/// The storefront's key is an Algolia *secured* key restricted by
/// `validUntil` to 24 hours after the page was rendered, so the app can't
/// ship one. Until the planned GraphQL `hmAppConfig { algolia { … } }`
/// (MagentoEgypt_HubApp) serves the settings, they are read the way the
/// website's own autocomplete reads them: from `window.algoliaConfig` on the
/// store view's home page — one GET of about 60 KB (gzip), which Magento's
/// full-page cache serves. That object also carries the index name, the
/// facets with their store-view labels and the sort replicas.
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
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 10),
  }) : _clock = clock ?? DateTime.now;

  final AppConfig _config;
  final http.Client _client;
  final LocalCache _cache;
  final Uri Function(String storeCode) _storefrontPage;
  final DateTime Function() _clock;
  final Duration timeout;

  final Map<String, AlgoliaSettings> _memory = {};
  final Map<String, Future<AlgoliaSettings>> _pending = {};

  static String _cacheKey(String storeCode) => 'algolia_settings_$storeCode';

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
    _memory.remove(storeCode);
    try {
      await _cache.deleteKey(_cacheKey(storeCode));
    } on Object {
      // A cache that can't be written only costs a refetch.
    }
  }

  Future<AlgoliaSettings> _fetch(String storeCode) async {
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
    if (!settings.usableAt(_clock())) {
      // The page came from a full-page cache older than its key.
      throw const AlgoliaUnavailable('the storefront key has expired');
    }

    _memory[storeCode] = settings;
    try {
      await _cache.writeString(
        _cacheKey(storeCode),
        jsonEncode(settings.toStorefrontConfig()),
      );
    } on Object {
      // Not persisted: the next launch reads the page again.
    }
    return settings;
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
  );
});
