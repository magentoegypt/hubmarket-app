import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Reads a Magento timestamp that carries **no offset** — `2026-09-16 13:46:00`
/// — as wall-clock time in the store's [ianaZone], and returns the same instant
/// in the device's zone.
///
/// Magento renders `order_date` in the store's timezone and drops the offset,
/// so parsing it with [DateTime.parse] silently re-labels it as device-local:
/// an order placed at 12:46 in Cairo came back as `13:46` (Dubai) and was shown
/// as "1:46 PM", an hour after the shopper's own clock. Anchoring it to the
/// store zone first makes the displayed time mean what it says.
///
/// Returns null when the string can't be parsed. An empty or unknown zone, or a
/// string that already carries an offset/`Z`, is returned as parsed — the
/// device's zone is then the best available guess, matching the pre-existing
/// behaviour rather than shifting by a guessed amount.
DateTime? storeStampToLocal(String raw, String ianaZone) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;
  // Already unambiguous (trailing Z or ±hh:mm) — tryParse resolved the instant.
  if (parsed.isUtc || _hasOffset(text)) return parsed.toLocal();
  final location = _location(ianaZone);
  if (location == null) return parsed;
  // Re-anchor the same wall-clock reading to the store's zone, then convert.
  return tz.TZDateTime(
    location,
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
  ).toLocal();
}

/// Whether an ISO-8601 string carries an explicit zone. Only the time half can:
/// the `-` in `2026-09-16` is a date separator, so scan after `T`/the space.
bool _hasOffset(String text) {
  final sep = text.indexOf(RegExp(r'[T ]'));
  if (sep < 0) return text.endsWith('Z');
  final time = text.substring(sep + 1);
  return time.endsWith('Z') || time.contains('+') || time.contains('-');
}

bool _dbReady = false;

/// Resolves an IANA zone name, loading the tz database on first use. Returns
/// null for an empty/unknown name so the caller can fall back.
tz.Location? _location(String ianaZone) {
  final name = ianaZone.trim();
  if (name.isEmpty) return null;
  if (!_dbReady) {
    // The 10-year database is ~1/5 the size of the full one and covers the
    // order dates the app shows.
    tzdata.initializeTimeZones();
    _dbReady = true;
  }
  try {
    return tz.getLocation(name);
  } catch (_) {
    return null;
  }
}
