#!/usr/bin/env bash
# Capture App Store screenshots on an iOS Simulator. macOS only — runs in CI
# (.github/workflows/screenshots-ios.yml); there is no local Mac.
#
# Drives the app in-process via `flutter drive` + integration_test, navigating
# through routerProvider. An earlier version drove it with `simctl openurl`
# deep links; that produced eight identical shots of the welcome screen,
# because hubmarket:// links do not route on iOS (the app sets neither
# FlutterDeepLinkingEnabled nor an openURL handler). The integration_test route
# also skips NotificationService.init(), so the iOS notification-permission
# alert never covers a screenshot.
#
# Simulator builds are debug-only on iOS (Flutter has no --profile/--release
# for the simulator); harmless here because debugShowCheckedModeBanner is
# already false.
set -euo pipefail

OUT_DIR="${OUT_DIR:-build/screenshots/ios}"
CONFIG_FILE="${CONFIG_FILE:-config/prod.json}"
LOCALE="${SHOT_LOCALE:-en}"

# App Store Connect's 6.5" slot accepts 1242x2688 or 1284x2778. Modern
# simulators render 1290x2796 (6.7"/6.9"), so normalise to 1284x2778 — the
# aspect ratios differ by <0.2%, which is imperceptible.
TARGET_W=1284
TARGET_H=2778

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ---- pick an available simulator (preference order, newest first) ----
UDID=""
DEVICE_NAME=""
for name in "iPhone 16 Plus" "iPhone 16 Pro Max" "iPhone 16" \
            "iPhone 15 Plus" "iPhone 15 Pro Max" "iPhone 14 Plus"; do
  line="$(xcrun simctl list devices available | grep -F "    ${name} (" | head -n1 || true)"
  if [[ -n "$line" ]]; then
    UDID="$(printf '%s' "$line" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
    DEVICE_NAME="$name"
    break
  fi
done
if [[ -z "$UDID" ]]; then
  echo "::error::No suitable iPhone simulator found. Available devices:" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "Using simulator: ${DEVICE_NAME} (${UDID})"

cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

# ---- drive ----
# A fresh install has no persisted locale, so it falls back to DEFAULT_LOCALE.
# Override it (and the store it bootstraps against) to capture the RTL set.
LOCALE_DEFINES=(--dart-define="SHOT_LOCALE=${LOCALE}")
if [[ "$LOCALE" == "ar" ]]; then
  LOCALE_DEFINES+=(--dart-define=DEFAULT_LOCALE=ar --dart-define=BOOTSTRAP_STORE_CODE=ar)
fi

echo "Driving screenshots (${CONFIG_FILE}, locale=${LOCALE})…"
flutter drive \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/screenshots_test.dart \
  -d "$UDID" \
  --dart-define-from-file="$CONFIG_FILE" \
  "${LOCALE_DEFINES[@]}"

shopt -s nullglob
shots=("$OUT_DIR"/*.png)
if (( ${#shots[@]} == 0 )); then
  echo "::error::No screenshots were written to ${OUT_DIR}" >&2
  exit 1
fi

# sips -z takes HEIGHT then WIDTH.
for f in "${shots[@]}"; do
  sips -z "$TARGET_H" "$TARGET_W" "$f" >/dev/null
done

# Identical files mean navigation silently failed (the old deep-link bug), so
# fail loudly here rather than shipping eight copies of one screen.
dupes="$(md5 -q "${shots[@]}" | sort | uniq -d | wc -l | tr -d ' ')"
if [[ "$dupes" != "0" ]]; then
  echo "::error::${dupes} duplicate screenshot(s) — navigation likely failed:" >&2
  md5 "${shots[@]}" >&2
  exit 1
fi

echo
echo "Done — ${#shots[@]} screenshots in ${OUT_DIR}:"
ls -la "$OUT_DIR"
