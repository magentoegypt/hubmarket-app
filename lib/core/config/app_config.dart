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
    required this.merchantName,
    required this.applePayMerchantId,
    required this.applePayCountryCode,
    required this.applePayNetworks,
    required this.samsungPayServiceId,
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

  /// Merchant display name shown on the Apple Pay / Samsung Pay sheet.
  final String merchantName;

  /// Apple Pay merchant identifier (`merchant.com.hubmarket.app`).
  ///
  /// A *hint*, not the source of truth: the value that actually matters is the
  /// one in `com.apple.developer.in-app-payments`, which ships from the
  /// provisioning profile. Blank means "not configured" and the Apple Pay row
  /// stays hidden, which is the safe default before the merchant account exists.
  final String applePayMerchantId;

  /// ISO country of the Apple Pay merchant — `AE`.
  final String applePayCountryCode;

  /// Comma-separated `PKPaymentNetwork` names (e.g. `visa,mastercard`). A config
  /// value rather than a native constant so the schemes enabled on the N-Genius
  /// outlet can be tuned without a native release.
  final String applePayNetworks;

  /// Samsung Pay Service ID from the Samsung Pay Developer portal. Blank means
  /// the Samsung Pay row stays hidden — and the native side must check this
  /// before constructing `SamsungPayClient`, which throws on a blank id.
  final String samsungPayServiceId;


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
    merchantName: String.fromEnvironment('MERCHANT_NAME', defaultValue: 'Hub Market'),
    applePayMerchantId: String.fromEnvironment(
      'APPLE_PAY_MERCHANT_ID',
      defaultValue: '',
    ),
    applePayCountryCode: String.fromEnvironment(
      'APPLE_PAY_COUNTRY_CODE',
      defaultValue: 'AE',
    ),
    applePayNetworks: String.fromEnvironment(
      'APPLE_PAY_NETWORKS',
      defaultValue: 'visa,mastercard',
    ),
    samsungPayServiceId: String.fromEnvironment(
      'SAMSUNG_PAY_SERVICE_ID',
      defaultValue: '',
    ),
  );

  bool get isProd => flavor == 'prod';

  /// Wallet identifiers the native `hubmarket/payments` module needs, on both
  /// `pay` and `walletAvailability`. Blank values are omitted so the native side
  /// can fall back to the entitlement / manifest value rather than being handed
  /// an empty string.
  Map<String, Object> get walletIdentifierArgs => <String, Object>{
    'merchantName': merchantName,
    if (applePayMerchantId.isNotEmpty) 'applePayMerchantId': applePayMerchantId,
    if (applePayCountryCode.isNotEmpty)
      'applePayCountryCode': applePayCountryCode,
    if (applePayNetworks.isNotEmpty)
      'applePayNetworks': applePayNetworks
          .split(',')
          .map((n) => n.trim())
          .where((n) => n.isNotEmpty)
          .toList(),
    if (samsungPayServiceId.isNotEmpty)
      'samsungPayServiceId': samsungPayServiceId,
  };

  /// Provisional `language -> store_code` fallback (`en`/`ar`).
  Map<String, String> get provisionalStoreCodes => <String, String>{
    'en': storeCodeEn,
    'ar': storeCodeAr,
  };
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.current);
