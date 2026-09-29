import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable application configuration sourced from `--dart-define-from-file`
/// (see `config/{dev,staging,prod}.json`).
///
/// Store codes here are **bootstrap/fallback** values only. The authoritative
/// `locale -> store_code` mapping, default view, and currency are resolved at
/// runtime from `availableStores` (see [StoreController]).
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.graphqlEndpoint,
    required this.defaultLocale,
    required this.bootstrapStoreCode,
    required this.storeCodeEn,
    required this.storeCodeAr,
    required this.currency,
    required this.userAgent,
    required this.algoliaAppId,
    required this.algoliaSearchKey,
    required this.algoliaIndexPrefix,
    required this.algoliaSortReplicas,
  });

  final String flavor;
  final String graphqlEndpoint;
  final String defaultLocale;

  /// Store view used for the very first `availableStores` request, before the
  /// real mapping is known.
  final String bootstrapStoreCode;

  /// Provisional codes used only as a fallback until `availableStores` resolves.
  final String storeCodeEn;
  final String storeCodeAr;

  final String currency;
  final String userAgent;

  // Algolia — the engine behind the storefront's search. The planned source
  // of all four is the backend: GraphQL `hmAppConfig { algolia {
  // application_id search_api_key index_prefix … } }` from the
  // MagentoEgypt_HubApp module (being built). Until it ships, the app reads
  // these compile-time values and, for the key, the storefront page's
  // `window.algoliaConfig` (see `AlgoliaSettingsRepository`).

  /// The Algolia application the storefront searches. Empty turns Algolia off:
  /// search then goes through GraphQL `products(search:)`.
  final String algoliaAppId;

  /// A static search-only key, normally empty. The storefront has none to
  /// give: its key is an Algolia *secured* key (`tagFilters`, `validUntil`)
  /// minted with every page render and valid for 24 hours, so it cannot ship
  /// in the app; the app reads the current one from the backend at run time.
  /// Setting a non-expiring search-only key here skips that lookup.
  final String algoliaSearchKey;

  /// Index-name prefix: a store view's indices are
  /// `<prefix><store code>_{products,categories,pages}`.
  final String algoliaIndexPrefix;

  /// The products index's sort replicas, comma-separated, as suffixes of
  /// `<prefix><store code>_products_` — only used when the backend's own list
  /// (`algoliaConfig.sortingIndices`) is unavailable.
  final String algoliaSortReplicas;

  static const AppConfig current = AppConfig(
    flavor: String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
    graphqlEndpoint: String.fromEnvironment(
      'GRAPHQL_ENDPOINT',
      defaultValue: 'https://hub-market.magento2.click/graphql',
    ),
    defaultLocale: String.fromEnvironment('DEFAULT_LOCALE', defaultValue: 'en'),
    bootstrapStoreCode: String.fromEnvironment(
      'BOOTSTRAP_STORE_CODE',
      defaultValue: 'en',
    ),
    storeCodeEn: String.fromEnvironment(
      'STORE_CODE_EN',
      defaultValue: 'en',
    ),
    storeCodeAr: String.fromEnvironment(
      'STORE_CODE_AR',
      defaultValue: 'ar',
    ),
    currency: String.fromEnvironment('CURRENCY', defaultValue: 'AED'),
    userAgent: String.fromEnvironment(
      'USER_AGENT',
      defaultValue: 'HubMarketApp/0.1.0 (Flutter)',
    ),
    algoliaAppId: String.fromEnvironment(
      'ALGOLIA_APP_ID',
      defaultValue: 'HL67ED06DQ',
    ),
    algoliaSearchKey: String.fromEnvironment('ALGOLIA_SEARCH_KEY'),
    algoliaIndexPrefix: String.fromEnvironment(
      'ALGOLIA_INDEX_PREFIX',
      defaultValue: 'hubmarket_',
    ),
    algoliaSortReplicas: String.fromEnvironment(
      'ALGOLIA_SORT_REPLICAS',
      defaultValue: 'price_default_asc,price_default_desc,created_at_desc',
    ),
  );

  bool get isProd => flavor == 'prod';

  /// Whether the app may search Algolia at all (an application and a prefix
  /// are configured). The key may still have to come from the backend.
  bool get algoliaConfigured =>
      algoliaAppId.trim().isNotEmpty && algoliaIndexPrefix.trim().isNotEmpty;

  /// [algoliaSortReplicas] as a list, blanks dropped.
  List<String> get algoliaSortReplicaSuffixes => algoliaSortReplicas
      .split(',')
      .map((suffix) => suffix.trim())
      .where((suffix) => suffix.isNotEmpty)
      .toList(growable: false);

  /// Provisional `language -> store_code` fallback (`en`/`ar`).
  Map<String, String> get provisionalStoreCodes => <String, String>{
    'en': storeCodeEn,
    'ar': storeCodeAr,
  };
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.current);
