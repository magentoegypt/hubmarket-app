import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';
import '../../../core/util/media.dart';
import '../domain/home_config.dart';

/// The `magentoegypt_beauty_config` bag — a flat `{path, value}` list holding
/// the home merchandising toggles + the countdown promo (`general/enable_*`,
/// `deals/countdown_*`, `deals/category_id`). Section *content* comes from the
/// dedicated home queries (see `home_sections_provider.dart`). Isolated from the
/// other storeConfig queries so an unknown field can only hide the new sections,
/// never break the rest of the home. Read from the live schema via
/// `bash tool/introspect.sh`.
const String _query = r'''
query HomeBeautyConfig {
  storeConfig {
    timezone
    magentoegypt_beauty_config {
      path
      value
    }
  }
}
''';

/// Parsed home merchandising config for the active store view. Refetches on a
/// store/language switch. Degrades to [HomeConfig.empty] on any error (missing
/// module, unknown field, network) so every new section is safe.
final homeConfigProvider = FutureProvider.autoDispose<HomeConfig>((ref) async {
  // Kept alive: small, slow-changing, and on the critical path of every home
  // paint — the splash pre-fetches it, and an autoDispose provider would throw
  // that result away the moment the splash's subscription ended. A store switch
  // still invalidates it via the activeStoreCode watch below.
  ref.keepAlive();
  final store = ref.watch(storeControllerProvider);
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(document: gql(_query), fetchPolicy: FetchPolicy.networkOnly),
    );
    if (result.hasException) return HomeConfig.empty;
    final cfg = result.data?['storeConfig'] as Map<String, dynamic>?;
    final list = cfg?['magentoegypt_beauty_config'] as List<dynamic>?;
    if (list == null) return HomeConfig.empty;

    final values = <String, String>{};
    for (final item in list.whereType<Map<String, dynamic>>()) {
      final path = (item['path'] as String?)?.trim();
      if (path == null || path.isEmpty) continue;
      values[path] = (item['value'] as String?)?.trim() ?? '';
    }

    return HomeConfig(
      flags: _flags(values),
      limitedTimeOffer: _limitedTimeOffer(
        values,
        _mediaBase(store),
        (cfg?['timezone'] as String?)?.trim() ?? '',
      ),
      dealsCategoryId: values['deals/category_id'] ?? '',
    );
  } catch (_) {
    return HomeConfig.empty;
  }
});

/// Pulls the `general/enable_*` switches into a prefix-free map so
/// [HomeConfig.sectionEnabled] can look them up by section key.
Map<String, String> _flags(Map<String, String> values) {
  const prefix = 'general/enable_';
  final flags = <String, String>{};
  for (final entry in values.entries) {
    if (entry.key.startsWith(prefix)) {
      flags[entry.key.substring(prefix.length)] = entry.value;
    }
  }
  return flags;
}

LimitedTimeOffer _limitedTimeOffer(
  Map<String, String> v,
  String mediaBase,
  String timezone,
) {
  final headline = v['deals/countdown_headline'] ?? '';
  return LimitedTimeOffer(
    enabled: _asBool(v['deals/countdown_enabled']),
    headline: headline,
    subtext: v['deals/countdown_subtext'] ?? '',
    ctaLabel: v['deals/countdown_cta_label'] ?? '',
    ctaUrl: v['deals/countdown_cta_url'] ?? '',
    imageUrl: resolveMediaUrl(v['deals/countdown_image'], mediaBase),
    mode: (v['deals/countdown_mode'] ?? 'daily'),
    timezone: timezone,
  );
}

/// Base media URL of the active store view (e.g. `https://hub-market.magento2.click/media/`),
/// used to resolve relative config image paths.
String _mediaBase(StoreState store) {
  for (final s in store.stores) {
    if (s.storeCode == store.activeStoreCode) return s.baseMediaUrl;
  }
  return store.stores.isNotEmpty ? store.stores.first.baseMediaUrl : '';
}

bool _asBool(Object? value) => switch (value) {
  final bool b => b,
  final num n => n != 0,
  final String s => s == '1' || s.toLowerCase() == 'true',
  _ => false,
};
