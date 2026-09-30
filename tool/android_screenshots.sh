#!/usr/bin/env bash
# Capture Google Play screenshots on a phone or emulator with the same integration test the iOS
# lane uses (integration_test/screenshots_test.dart), then fit them to Play's rules
# (tool/fit_play_screenshots.py). Runs against the LIVE backend, so the shots show whatever the
# catalogue holds at that moment.
#
#   bash tool/android_screenshots.sh                  # English, dev flavor, the one attached device
#   SHOT_LOCALE=ar bash tool/android_screenshots.sh   # Arabic (RTL)
#   DEVICE=<adb serial> FLAVOR=dev bash tool/android_screenshots.sh
#
# Needs Flutter, adb with a device attached, and Python with Pillow for the fitting step. A debug
# build is installed on the device: the dev flavor (com.hubmarket.app.dev) keeps the QA build.
#
# Raw captures land in build/screenshots/android/raw, the Play-ready ones in .../play.
# The shot list and what to replace once the catalogue is real: docs/release/screenshots.md.
set -euo pipefail

LOCALE="${SHOT_LOCALE:-en}"
FLAVOR="${FLAVOR:-dev}"
CONFIG_FILE="${CONFIG_FILE:-config/${FLAVOR}.json}"
OUT_DIR="${OUT_DIR:-build/screenshots/android}"
RAW_DIR="${OUT_DIR}/raw"
PLAY_DIR="${OUT_DIR}/play"

rm -rf "$RAW_DIR" "$PLAY_DIR"
mkdir -p "$RAW_DIR" "$PLAY_DIR"

DEVICE_ARGS=()
if [[ -n "${DEVICE:-}" ]]; then
  DEVICE_ARGS=(-d "$DEVICE")
fi

# A fresh install has no persisted locale, so it falls back to DEFAULT_LOCALE. Override it (and
# the store it bootstraps against) to capture the RTL set.
LOCALE_DEFINES=(--dart-define="SHOT_LOCALE=${LOCALE}")
if [[ "$LOCALE" == "ar" ]]; then
  LOCALE_DEFINES+=(--dart-define=DEFAULT_LOCALE=ar --dart-define=BOOTSTRAP_STORE_CODE=ar)
fi

export SHOT_OUT_DIR="$RAW_DIR"

echo "Driving screenshots (${CONFIG_FILE}, flavor=${FLAVOR}, locale=${LOCALE})…"
flutter drive \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/screenshots_test.dart \
  ${DEVICE_ARGS[@]+"${DEVICE_ARGS[@]}"} \
  --flavor "$FLAVOR" \
  --dart-define-from-file="$CONFIG_FILE" \
  "${LOCALE_DEFINES[@]}"

shopt -s nullglob
shots=("$RAW_DIR"/*.png)
if (( ${#shots[@]} == 0 )); then
  echo "No screenshots were written to ${RAW_DIR}" >&2
  exit 1
fi

# Identical files mean navigation silently failed, so fail loudly rather than ship copies of one
# screen.
dupes="$(md5sum "${shots[@]}" | awk '{print $1}' | sort | uniq -d | wc -l | tr -d ' ')"
if [[ "$dupes" != "0" ]]; then
  echo "${dupes} duplicate screenshot(s): navigation likely failed" >&2
  md5sum "${shots[@]}" >&2
  exit 1
fi

python tool/fit_play_screenshots.py "$RAW_DIR" "$PLAY_DIR"

echo
echo "Done: ${#shots[@]} screenshots. Raw in ${RAW_DIR}, Play-ready in ${PLAY_DIR}"
