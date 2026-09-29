import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:graphql_flutter/graphql_flutter.dart';

import '../../../core/graphql/graphql_client.dart';
import '../../../core/store/store_controller.dart';

/// Admin-configured "Special Offer Banner" (Magento system config, store-view
/// scoped — Enabled / Offer Text / Coupon Code). Read from `storeConfig` at
/// runtime so merchandising is controlled from the backend, not the app.
class SpecialOffer {
  const SpecialOffer({this.enabled = false, this.text = '', this.couponCode = ''});

  final bool enabled;
  final String text;
  final String couponCode;

  /// The banner shows only when enabled with offer text; the coupon line is
  /// shown only when a code is set ("leave empty to hide").
  bool get isVisible => enabled && text.isNotEmpty;
  bool get hasCode => couponCode.isNotEmpty;

  static const SpecialOffer hidden = SpecialOffer();
}

// Isolated from the main storeConfig query so an unknown field (e.g. before the
// backend module is deployed) only hides the banner — it can't break the rest
// of the app. Field names map from the admin config paths
// magentoegypt_beauty/offer/{enabled,text,code} (slashes -> underscores), as
// exposed on StoreConfig. tool/introspect.sh prints the live names to confirm.
const String _query = r'''
query SpecialOfferConfig {
  storeConfig {
    magentoegypt_beauty_offer_enabled
    magentoegypt_beauty_offer_text
    magentoegypt_beauty_offer_code
  }
}
''';

bool _asBool(Object? value) => switch (value) {
  final bool b => b,
  final num n => n != 0,
  final String s => s == '1' || s.toLowerCase() == 'true',
  _ => false,
};

/// Admin-configured announcement bar message (magentoegypt_beauty/announcement/
/// message). Isolated from the offer query so one unknown field can't break the
/// other. Returns '' on error/absence — the bar then shows its default text.
const String _announcementQuery = r'''
query AnnouncementConfig {
  storeConfig {
    magentoegypt_beauty_announcement_message
  }
}
''';

final announcementMessageProvider = FutureProvider.autoDispose<String>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(
        document: gql(_announcementQuery),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) return '';
    final cfg = result.data?['storeConfig'] as Map<String, dynamic>?;
    return (cfg?['magentoegypt_beauty_announcement_message'] as String?)
            ?.trim() ??
        '';
  } catch (_) {
    return '';
  }
});

/// Refetches on store/language switch. Degrades to [SpecialOffer.hidden] on any
/// error (missing module, unknown field, network) so the home screen is safe.
final specialOfferProvider = FutureProvider.autoDispose<SpecialOffer>((
  ref,
) async {
  ref.watch(storeControllerProvider.select((s) => s.activeStoreCode));
  final client = ref.watch(graphqlClientProvider);
  try {
    final result = await client.query(
      QueryOptions(
        document: gql(_query),
        fetchPolicy: FetchPolicy.networkOnly,
      ),
    );
    if (result.hasException) return SpecialOffer.hidden;
    final cfg = result.data?['storeConfig'] as Map<String, dynamic>?;
    if (cfg == null) return SpecialOffer.hidden;
    return SpecialOffer(
      enabled: _asBool(cfg['magentoegypt_beauty_offer_enabled']),
      text: (cfg['magentoegypt_beauty_offer_text'] as String?)?.trim() ?? '',
      couponCode:
          (cfg['magentoegypt_beauty_offer_code'] as String?)?.trim() ?? '',
    );
  } catch (_) {
    return SpecialOffer.hidden;
  }
});
