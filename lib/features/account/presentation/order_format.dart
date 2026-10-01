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

/// "28 Sep 2026, 10:42": when an order was placed (Figma 22), on the 24-hour
/// clock, read in [storeZone] like [orderFmtDate].
String orderFmtPlaced(String raw, [String? locale, String storeZone = '']) {
  final dt = storeStampToLocal(raw, storeZone);
  return dt == null
      ? raw
      : formatStamp(dt, 'd MMM yyyy${_comma(locale)} HH:mm', locale);
}

/// The comma between a date and its time: Arabic writes "،" (Figma 22 AR).
String _comma(String? locale) =>
    locale == 'ar' ? String.fromCharCode(0x060c) : ',';

/// "28 Sep, 10:42": a step of a package's timeline (Figma 22), on the 24-hour
/// clock, read in [storeZone] like [orderFmtDate].
String orderFmtStep(String raw, [String? locale, String storeZone = '']) {
  final dt = storeStampToLocal(raw, storeZone);
  return dt == null ? raw : orderFmtStepAt(dt, locale);
}

/// [orderFmtStep] of a moment the server gave with its own offset (a shipment,
/// a store's comment), shown in the device's zone.
String orderFmtStepAt(DateTime dt, [String? locale]) =>
    formatStamp(dt.toLocal(), 'd MMM${_comma(locale)} HH:mm', locale);

/// [dt] by [pattern] in [locale]; the default locale when [locale]'s date
/// symbols aren't loaded.
String formatStamp(DateTime dt, String pattern, [String? locale]) {
  try {
    return DateFormat(pattern, locale).format(dt);
  } catch (_) {
    return DateFormat(pattern).format(dt);
  }
}
