#!/usr/bin/env bash
# Proves that hubmarket://app/... URLs actually navigate on iOS. macOS only —
# runs in CI (.github/workflows/verify-deeplinks-ios.yml).
#
# Why this exists: the app shipped without FlutterDeepLinkingEnabled, so iOS
# foregrounded the app on a deep link but never routed — a password-reset link
# landed the user on Home. Android was unaffected (its intent-filter drives
# Flutter's built-in handling). The plist key is the fix; this script is the
# evidence, because the bug is invisible from the Windows dev machine.
#
# Method: screenshot the app, fire a deep link, screenshot again, and require
# the two to differ. The iOS notification-permission alert is present in both
# frames, so it cancels out — any hash difference is the screen behind it
# changing, which is exactly what we're testing.
set -euo pipefail

CONFIG_FILE="${CONFIG_FILE:-config/prod.json}"
BUNDLE_ID="${BUNDLE_ID:-com.hubmarket.app}"
WORK="${WORK:-build/deeplink-verify}"

rm -rf "$WORK"
mkdir -p "$WORK"

UDID=""
for name in "iPhone 16 Plus" "iPhone 16 Pro Max" "iPhone 16" \
            "iPhone 15 Plus" "iPhone 15 Pro Max" "iPhone 14 Plus"; do
  line="$(xcrun simctl list devices available | grep -F "    ${name} (" | head -n1 || true)"
  if [[ -n "$line" ]]; then
    UDID="$(printf '%s' "$line" | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
    echo "Using simulator: ${name} (${UDID})"
    break
  fi
done
[[ -n "$UDID" ]] || { echo "::error::No suitable iPhone simulator found" >&2; exit 1; }

cleanup() { xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; }
trap cleanup EXIT

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b

echo "Building simulator app…"
flutter build ios --simulator --debug --dart-define-from-file="$CONFIG_FILE"
xcrun simctl install "$UDID" build/ios/iphonesimulator/Runner.app

# Confirm the key actually made it into the installed bundle — a silent drop
# here would look identical to a routing failure.
PLIST="build/ios/iphonesimulator/Runner.app/Info.plist"
if ! /usr/libexec/PlistBuddy -c "Print :FlutterDeepLinkingEnabled" "$PLIST" 2>/dev/null | grep -qi true; then
  echo "::error::FlutterDeepLinkingEnabled is not true in the built bundle" >&2
  exit 1
fi
echo "FlutterDeepLinkingEnabled=true confirmed in bundle"

xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null
sleep 30   # splash -> store bootstrap -> welcome

xcrun simctl io "$UDID" screenshot --type=png "$WORK/before.png"

fail=0
check() {
  local label="$1" url="$2"
  xcrun simctl openurl "$UDID" "$url"
  sleep 12
  xcrun simctl io "$UDID" screenshot --type=png "$WORK/after-${label}.png"
  if [[ "$(md5 -q "$WORK/before.png")" == "$(md5 -q "$WORK/after-${label}.png")" ]]; then
    echo "::error::${label}: screen unchanged after ${url} — deep link did not route"
    fail=1
  else
    echo "OK  ${label}: ${url} navigated"
  fi
}

check "product"  "hubmarket://app/product/3616306115934"
check "category" "hubmarket://app/category/Mw=="
check "cart"     "hubmarket://app/cart"

exit "$fail"
