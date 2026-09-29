import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/local_cache.dart';

/// Persisted key for the marketing email-offers opt-in.
const String kEmailOffersPrefKey = 'pref_email_offers';

/// Whether marketing email offers are enabled (default on). Persisted locally.
/// Backend newsletter sync (Magento customer `is_subscribed`) is a follow-up;
/// for now this stores the user's choice on-device.
class EmailOffersSettings extends Notifier<bool> {
  @override
  bool build() =>
      ref.read(localCacheProvider).readString(kEmailOffersPrefKey) != 'false';

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref
        .read(localCacheProvider)
        .writeString(kEmailOffersPrefKey, '$enabled');
  }
}

final emailOffersProvider = NotifierProvider<EmailOffersSettings, bool>(
  EmailOffersSettings.new,
);
