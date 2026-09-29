import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../graphql/graphql_client.dart';
import '../store/store_controller.dart';

/// Store contact details + social links — a single source of truth consumed by
/// the About screen, Help & FAQ, and the marketing footer.
///
/// Sourced from **admin config**: `MagentoEgypt_Beauty` exposes the whole
/// `magentoegypt_beauty/*` section on `StoreConfig` as a generic
/// `magentoegypt_beauty_config { path value }` list (store-scoped, so the
/// Arabic store returns Arabic footer text). The relevant paths are
/// `footer/business_{name,address,phone,email,hours}`, `footer/{facebook,
/// instagram,tiktok,pinterest,youtube,twitter}_url`, and `whatsapp/phone`.
/// Falls back to the live store's verified values while loading or if the
/// backend doesn't return them.
class StoreContact {
  const StoreContact({
    required this.company,
    required this.address,
    required this.phone,
    required this.phoneDisplay,
    required this.email,
    required this.hours,
    required this.whatsapp,
    required this.website,
    this.facebook,
    this.instagram,
    this.tiktok,
    this.pinterest,
    this.youtube,
    this.twitter,
  });

  final String company;
  final String address;

  /// E.164 number for `tel:` links.
  final String phone;

  /// Human-formatted number for display.
  final String phoneDisplay;
  final String email;

  /// Business hours (admin text), empty when unset.
  final String hours;

  /// Full `https://wa.me/...` URL.
  final String whatsapp;
  final String website;

  /// Social profile URLs — null when the store has no presence there.
  final String? facebook;
  final String? instagram;
  final String? tiktok;
  final String? pinterest;
  final String? youtube;
  final String? twitter;

  /// Non-null social links keyed by network, in display order.
  List<({String key, String url})> get socials => [
    // Figma footer order: Instagram · X · YouTube · Facebook (then the rest).
    if (instagram != null) (key: 'instagram', url: instagram!),
    if (twitter != null) (key: 'twitter', url: twitter!),
    if (youtube != null) (key: 'youtube', url: youtube!),
    if (facebook != null) (key: 'facebook', url: facebook!),
    if (tiktok != null) (key: 'tiktok', url: tiktok!),
    if (pinterest != null) (key: 'pinterest', url: pinterest!),
  ];
}

/// Verified live values, used until the admin config loads / if it's absent.
const StoreContact _fallback = StoreContact(
  company: 'Hub Market Perfume & Cosmetics Trading LLC',
  address:
      'HHHR Tower, Sheikh Zayed Road, Trade Center First, Dubai, United Arab Emirates',
  phone: '+971505104167',
  phoneDisplay: '+971 50 510 4167',
  email: 'info@hub-market.magento2.click',
  hours: '',
  whatsapp: 'https://wa.me/971505104167',
  website: 'https://hub-market.magento2.click',
  facebook: 'https://www.facebook.com/share/1UYpE6ebzx/?mibextid=wwXIfr',
  instagram: 'https://www.instagram.com/zoon.ze/',
);

const String _query = r'''
query StoreContactConfig {
  storeConfig {
    magentoegypt_beauty_config { path value }
  }
}
''';

/// The admin `magentoegypt_beauty/*` section as a `path -> value` map. Isolated
/// so an unknown field can't break the rest of the app; refetches on store /
/// language switch. Empty on error/absence (fallback contact applies).
final beautyConfigProvider = FutureProvider.autoDispose<Map<String, String>>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(document: gql(_query), fetchPolicy: FetchPolicy.networkOnly),
    );
    if (result.hasException) return const {};
    final list =
        (result.data?['storeConfig']
                as Map<String, dynamic>?)?['magentoegypt_beauty_config']
            as List<dynamic>?;
    if (list == null) return const {};
    final map = <String, String>{};
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        final p = e['path'] as String?;
        final v = e['value'] as String?;
        if (p != null && v != null) map[p] = v;
      }
    }
    return map;
  } catch (_) {
    return const {};
  }
});

/// Store contact + social links from admin config, with verified fallbacks.
final storeContactProvider = Provider.autoDispose<StoreContact>((ref) {
  final cfg = ref.watch(beautyConfigProvider).valueOrNull;
  // Not loaded yet / failed → the known values (so screens never look empty).
  if (cfg == null || cfg.isEmpty) return _fallback;

  String? v(String path) {
    final s = cfg[path]?.trim();
    // Treat blank / nbsp placeholder as unset.
    return (s == null || s.isEmpty || s == ' ') ? null : s;
  }

  final waPhone = v('whatsapp/phone');
  return StoreContact(
    company: v('footer/business_name') ?? _fallback.company,
    address: v('footer/business_address') ?? _fallback.address,
    phoneDisplay: v('footer/business_phone') ?? _fallback.phoneDisplay,
    phone: waPhone != null ? '+$waPhone' : _fallback.phone,
    email: v('footer/business_email') ?? _fallback.email,
    hours: v('footer/business_hours') ?? '',
    whatsapp: waPhone != null ? 'https://wa.me/$waPhone' : _fallback.whatsapp,
    website: _fallback.website,
    // Socials come straight from config once loaded (null = admin left blank).
    facebook: v('footer/facebook_url'),
    instagram: v('footer/instagram_url'),
    tiktok: v('footer/tiktok_url'),
    pinterest: v('footer/pinterest_url'),
    youtube: v('footer/youtube_url'),
    twitter: v('footer/twitter_url'),
  );
});
