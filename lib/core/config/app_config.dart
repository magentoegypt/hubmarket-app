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
  );

  bool get isProd => flavor == 'prod';

  /// Provisional `language -> store_code` fallback (`en`/`ar`).
  Map<String, String> get provisionalStoreCodes => <String, String>{
    'en': storeCodeEn,
    'ar': storeCodeAr,
  };
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.current);
