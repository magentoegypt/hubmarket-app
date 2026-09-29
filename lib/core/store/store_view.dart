/// A Magento store view as returned by `availableStores`. The authoritative
/// source for store code, locale, currency, and base URLs — never hardcoded.
class StoreView {
  const StoreView({
    required this.storeCode,
    required this.storeName,
    required this.locale,
    required this.isDefault,
    required this.baseCurrencyCode,
    required this.displayCurrencyCode,
    required this.baseUrl,
    required this.secureBaseUrl,
    required this.baseMediaUrl,
    this.baseLinkUrl = '',
  });

  final String storeCode;
  final String storeName;

  /// Magento locale, e.g. `en_US`, `ar_SA`.
  final String locale;
  final bool isDefault;
  final String baseCurrencyCode;
  final String displayCurrencyCode;
  final String baseUrl;
  final String secureBaseUrl;
  final String baseMediaUrl;

  /// Storefront-linked base URL — carries the PWA language path (`…/uae-ar/`)
  /// that CMS/content pages are served under. Unlike [secureBaseUrl] (the bare
  /// Magento base `…hub-market.magento2.click/`), this keeps the store view's URL prefix, so a
  /// per-locale content link lands on the right store instead of the default.
  final String baseLinkUrl;

  /// App language key derived from the Magento locale (`en_US` -> `en`).
  String get languageCode => locale.split(RegExp('[_-]')).first.toLowerCase();

  /// Currency to display: prefer the configured display currency, fall back to
  /// the base currency.
  String get currency =>
      displayCurrencyCode.isNotEmpty ? displayCurrencyCode : baseCurrencyCode;

  factory StoreView.fromJson(Map<String, dynamic> json) => StoreView(
    storeCode: (json['store_code'] as String?) ?? '',
    storeName: (json['store_name'] as String?) ?? '',
    locale: (json['locale'] as String?) ?? '',
    isDefault: (json['is_default_store'] as bool?) ?? false,
    baseCurrencyCode: (json['base_currency_code'] as String?) ?? '',
    displayCurrencyCode:
        (json['default_display_currency_code'] as String?) ?? '',
    baseUrl: (json['base_url'] as String?) ?? '',
    secureBaseUrl: (json['secure_base_url'] as String?) ?? '',
    baseMediaUrl: (json['base_media_url'] as String?) ?? '',
    baseLinkUrl: (json['base_link_url'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'store_code': storeCode,
    'store_name': storeName,
    'locale': locale,
    'is_default_store': isDefault,
    'base_currency_code': baseCurrencyCode,
    'default_display_currency_code': displayCurrencyCode,
    'base_url': baseUrl,
    'secure_base_url': secureBaseUrl,
    'base_media_url': baseMediaUrl,
    'base_link_url': baseLinkUrl,
  };
}
