import 'package:intl/intl.dart';

import '../../../core/util/store_time.dart';

/// Formats a Magento order timestamp (e.g. `2026-06-25 10:24:33`) as a short
/// date in the active [locale] (so AR renders Arabic month names) — falls back
/// to the raw string when it can't be parsed, and to the default locale if the
/// locale's date symbols aren't loaded.
///
/// [storeZone] is `storeConfig { timezone }`. Magento returns these timestamps
/// as store wall-clock with no offset, so they're re-anchored to that zone and
/// shown in the device's — see [storeStampToLocal]. An empty zone keeps the
/// previous reading (the string as device-local).
String orderFmtDate(String raw, [String? locale, String storeZone = '']) {
  final dt = storeStampToLocal(raw, storeZone);
  if (dt == null) return raw;
  try {
    return DateFormat('d MMM yyyy', locale).format(dt);
  } catch (_) {
    return DateFormat('d MMM yyyy').format(dt);
  }
}

/// Formats a Magento order timestamp as a short date + time
/// (e.g. `25 Jun, 10:24 AM`), localized to [locale] and read in [storeZone]
/// exactly as [orderFmtDate] does.
String orderFmtDateTime(String raw, [String? locale, String storeZone = '']) {
  final dt = storeStampToLocal(raw, storeZone);
  if (dt == null) return raw;
  try {
    return DateFormat('d MMM, h:mm a', locale).format(dt);
  } catch (_) {
    return DateFormat('d MMM, h:mm a').format(dt);
  }
}
