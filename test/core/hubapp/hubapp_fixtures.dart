/// `hmAppConfig` as the contract serves it (store view `en`), for the tests.
Map<String, dynamic> hmAppConfigJson({
  String storeCode = 'en',
  bool maintenance = false,
  String? minVersion = '1.0.0',
  String? latestVersion = '1.2.0',
  Map<String, dynamic>? algolia,
  Map<String, dynamic>? shipping,
}) => {
  'store_code': storeCode,
  'locale': storeCode == 'ar' ? 'ar_SA' : 'en_US',
  'search': {
    'hint': storeCode == 'ar' ? 'ابحث في هب ماركت' : 'Search Hub Market',
    'trending_terms': ['iphone', ' ', 'abaya', 'rice'],
  },
  'algolia': algolia,
  'contact': {
    'whatsapp_number': '+971501234567',
    'whatsapp_url': null,
    'phone': '+97145550000',
    'email': 'care@hub-market.example',
    'hours': 'Daily 9 am – 11 pm',
  },
  'version': [
    {
      'platform': 'ANDROID',
      'min_version': minVersion,
      'latest_version': latestVersion,
      'store_url': 'https://play.google.com/store/apps/details?id=hub.market',
      'message': 'A new version is ready.',
    },
    {'platform': 'WINDOWS', 'min_version': '9.9.9'},
  ],
  'maintenance': {
    'enabled': maintenance,
    'message': maintenance ? 'Back soon — stocktaking.' : null,
    'retry_after_minutes': maintenance ? 30 : null,
  },
  'features': [
    {'code': 'returns', 'enabled': true},
    {'code': 'store_credit', 'enabled': false},
    {'code': '', 'enabled': true},
  ],
  if (shipping != null) 'shipping': shipping,
};
