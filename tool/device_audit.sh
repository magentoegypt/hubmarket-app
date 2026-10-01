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
# A phone only: the Android phone's OS asks on the screen for a tap on Install each run, and it must stay
# unlocked with the screen on. flutter gives up after three unanswered prompts (about 75 s), so by default
# the APK is built first and then offered to the phone again and again (`adb install`, a prompt every 30 s,
# INSTALL_TRIES times, about 12 minutes by default) until someone taps Install; the test then runs on the
# installed build. INSTALL_TRIES=0 leaves the install to flutter drive (three prompts).
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

INSTALL_TRIES="${INSTALL_TRIES:-25}"
APK_ARGS=()
if [[ "$INSTALL_TRIES" -gt 0 && -n "${DEVICE:-}" ]]; then
  flutter build apk --debug --flavor "$FLAVOR" --target="$TARGET" "${DEFINES[@]}"
  APK="build/app/outputs/flutter-apk/app-${FLAVOR}-debug.apk"
  installed=0
  for ((try = 1; try <= INSTALL_TRIES; try++)); do
    echo "INSTALL offer $try of $INSTALL_TRIES: tap Install on the phone"
    if adb -s "$DEVICE" install -r -t "$APK" 2>&1 | grep -q "Success"; then
      installed=1
      echo "INSTALL accepted on offer $try"
      break
    fi
    sleep 2
  done
  if [[ "$installed" -ne 1 ]]; then
    echo "INSTALL never accepted: nothing was run"
    exit 1
  fi
  APK_ARGS=(--use-application-binary="$APK")
fi

flutter drive   --driver=test_driver/screenshot_driver.dart   --target="$TARGET"   ${DEVICE_ARGS[@]+"${DEVICE_ARGS[@]}"}   --flavor "$FLAVOR"   ${APK_ARGS[@]+"${APK_ARGS[@]}"}   "${DEFINES[@]}" 2>&1 | tee "$OUT_DIR/run.log"

echo
grep -a "^I/flutter.*AUDIT\|^AUDIT" "$OUT_DIR/run.log" | grep -a "done\|view" || true
echo "Captures: $(ls "$OUT_DIR"/*.png 2>/dev/null | wc -l) in $OUT_DIR. Compare: python tool/ui_audit/device_pairs.py en"
