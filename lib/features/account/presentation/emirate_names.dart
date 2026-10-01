import '../../../core/address/regions.dart';
import '../../../l10n/l10n.dart';

/// The emirate in the language of the page. The store defines no regions for the
/// UAE, so an address keeps the emirate as the English name the picker offered
/// ([uaeFallbackRegions]); this reads it back as "دبي" in Arabic. A name that is
/// none of the seven (typed on the website, or a store's own region) is shown as
/// it is.
String emirateLabel(AppLocalizations l10n, String name) {
  final wanted = name.trim().toLowerCase();
  for (final region in uaeFallbackRegions) {
    if (region.name.toLowerCase() == wanted) {
      return l10n.emirateName(region.code);
    }
  }
  return name.trim();
}
