#!/usr/bin/env bash
# Mounts every Figma screen on a phone (integration_test/device_audit_test.dart: the real widgets with the
# fakes of the widget tests, no login, no network) and writes the captures to build/device_audit, one PNG per
# screen state, in English and Arabic. The log (build/device_audit/run.log) lists every layout overflow or other
# framework error a screen raised, as `AUDIT ... !` lines. Guide: docs/device-audit.md.
#
#   bash tool/device_audit.sh                                    # every scene, en + ar
#   AUDIT_ONLY=E21,E22 AUDIT_LOCALES=ar bash tool/device_audit.sh
#   DEVICE=<adb serial> OUT_DIR=build/device_audit bash tool/device_audit.sh
#   TARGET=integration_test/device_check_test.dart bash tool/device_audit.sh   # the audit AND the live store
#                                                                              # screenshots (SHOT_LOCALE) in one run
#
# A phone only: the Android phone's OS asks on the screen for a tap on Install each run (and the run quits
# after three unanswered prompts), and it must stay unlocked with the screen on. Hold it, unlocked, and tap
# Install when the prompt shows (about a minute after the build starts).
set -euo pipefail

FLAVOR="${FLAVOR:-dev}"
TARGET="${TARGET:-integration_test/device_audit_test.dart}"
SHOT_LOCALE="${SHOT_LOCALE:-en}"
CONFIG_FILE="${CONFIG_FILE:-config/${FLAVOR}.json}"
OUT_DIR="${OUT_DIR:-build/device_audit}"
mkdir -p "$OUT_DIR"
if [[ -z "${AUDIT_ONLY:-}" && -z "${AUDIT_KEEP:-}" ]]; then
  rm -f "$OUT_DIR"/*.png
fi

DEVICE_ARGS=()
if [[ -n "${DEVICE:-}" ]]; then
  DEVICE_ARGS=(-d "$DEVICE")
fi

DEFINES=(--dart-define-from-file="$CONFIG_FILE" --dart-define="SHOT_LOCALE=${SHOT_LOCALE}")
# A fresh install has no persisted locale, so the store screenshots of the Arabic set start from these.
if [[ "$SHOT_LOCALE" == "ar" ]]; then
  DEFINES+=(--dart-define=DEFAULT_LOCALE=ar --dart-define=BOOTSTRAP_STORE_CODE=ar)
fi
if [[ -n "${AUDIT_ONLY:-}" ]]; then
  DEFINES+=(--dart-define="AUDIT_ONLY=${AUDIT_ONLY}")
fi
if [[ -n "${AUDIT_LOCALES:-}" ]]; then
  DEFINES+=(--dart-define="AUDIT_LOCALES=${AUDIT_LOCALES}")
fi

export SHOT_OUT_DIR="$OUT_DIR"
flutter drive \
  --driver=test_driver/screenshot_driver.dart \
  --target=integration_test/device_audit_test.dart \
  ${DEVICE_ARGS[@]+"${DEVICE_ARGS[@]}"} \
  --flavor "$FLAVOR" \
  "${DEFINES[@]}" 2>&1 | tee "$OUT_DIR/run.log"

echo
grep -a "^I/flutter.*AUDIT\|^AUDIT" "$OUT_DIR/run.log" | grep -a "done\|view" || true
echo "Captures: $(ls "$OUT_DIR"/*.png 2>/dev/null | wc -l) in $OUT_DIR. Compare: python tool/ui_audit/device_pairs.py en"
