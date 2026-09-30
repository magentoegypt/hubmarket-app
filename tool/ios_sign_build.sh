#!/usr/bin/env bash
# Build a SIGNED ad-hoc IPA from a distribution certificate (.p12) + ad-hoc
# provisioning profile (.mobileprovision) in ios/signing/ — no fastlane
# `match`, no separate signing repo. macOS only. ios/signing/ is git-ignored
# (the repo is public): release-ios.yml / build-ios.yml decode the files there
# from secrets; locally, copy them in by hand.
#
# Required:
#   - ios/signing/*.p12              Apple Distribution cert exported WITH its
#                                    private key, protected by a password
#   - ios/signing/*.mobileprovision  ad-hoc profile for the app id, including
#                                    your test devices' UDIDs
#   - env IOS_P12_PASSWORD           the password that protects the .p12
#
# Output: build/ios/ipa/*.ipa (signed, installable OTA on the profile's devices).
set -euo pipefail

SIGN_DIR="ios/signing"
P12="$(ls "${SIGN_DIR}"/*.p12 2>/dev/null | head -1 || true)"
: "${IOS_P12_PASSWORD:?IOS_P12_PASSWORD is required}"
[ -n "${P12}" ] || { echo "::error::No .p12 found in ${SIGN_DIR}"; exit 1; }

# Select the AD-HOC profile: pick the first .mobileprovision whose decoded plist
# HAS a `ProvisionedDevices` key (ad-hoc/dev profiles list device UDIDs; an
# App Store profile lying next to it never does). Without this, a plain
# `ls | head -1` would alphabetically pick the App Store profile and this ad-hoc
# build would sign with the wrong (device-less) profile.
PROFILE=""
for p in "${SIGN_DIR}"/*.mobileprovision; do
  [ -e "$p" ] || continue
  if security cms -D -i "$p" 2>/dev/null | grep -q "ProvisionedDevices"; then
    PROFILE="$p"; break
  fi
done
[ -n "${PROFILE}" ] || { echo "::error::No ad-hoc profile (one with ProvisionedDevices) found in ${SIGN_DIR}"; exit 1; }
echo "Cert: ${P12}"
echo "Ad-hoc profile: ${PROFILE}"

# 1) Create a dedicated keychain and import the distribution cert into it.
KEYCHAIN="${RUNNER_TEMP:-/tmp}/hubmarket-signing.keychain-db"
KCPW="ci-$(date +%s 2>/dev/null || echo pw)-$$"
security create-keychain -p "${KCPW}" "${KEYCHAIN}"
security set-keychain-settings -lut 21600 "${KEYCHAIN}"
security unlock-keychain -p "${KCPW}" "${KEYCHAIN}"
security import "${P12}" -k "${KEYCHAIN}" -P "${IOS_P12_PASSWORD}" \
  -T /usr/bin/codesign -T /usr/bin/security -f pkcs12
# Allow codesign to use the imported key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "${KCPW}" "${KEYCHAIN}" >/dev/null
# Add our keychain to the search list (keep the existing ones too).
security list-keychains -d user -s "${KEYCHAIN}" $(security list-keychains -d user | sed 's/["[:space:]]//g')

# 2) Read the profile's metadata (it's a CMS-signed plist).
PROFILE_PLIST="$(security cms -D -i "${PROFILE}")"
pb() { /usr/libexec/PlistBuddy -c "Print :$1" /dev/stdin <<<"${PROFILE_PLIST}" 2>/dev/null; }
PROFILE_UUID="$(pb UUID)"
PROFILE_NAME="$(pb Name)"
TEAM_ID="$(pb TeamIdentifier:0)"
APP_ID_FULL="$(pb Entitlements:application-identifier)"   # TEAMID.com.hubmarket.app
BUNDLE_ID="${APP_ID_FULL#*.}"
echo "Profile name='${PROFILE_NAME}' uuid=${PROFILE_UUID} team=${TEAM_ID} bundle=${BUNDLE_ID}"

# 3) Install the profile where Xcode looks for it.
PROFILES_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "${PROFILES_DIR}"
cp "${PROFILE}" "${PROFILES_DIR}/${PROFILE_UUID}.mobileprovision"

# 4) Generate ExportOptions for manual ad-hoc signing from the real values.
EXPORT_PLIST="${RUNNER_TEMP:-/tmp}/ExportOptions-AdHoc.plist"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>ad-hoc</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>provisioningProfiles</key><dict>
    <key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string>
  </dict>
  <key>uploadSymbols</key><true/>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict></plist>
PLIST

# 5) Build the signed IPA.
#
# We deliberately do NOT use `flutter build ipa` here. That wrapper runs the
# `xcodebuild archive` phase using the *project's* signing settings — and the
# committed Runner target is CODE_SIGN_STYLE=Automatic (correct for local dev
# and the App Store / fastlane match path). On a CI runner with no Apple ID,
# automatic signing can't provision and the archive fails with "No development
# certificates available", regardless of the export-options plist (which only
# governs the later export step).
#
# Instead: generate the Flutter build config, then archive + export with
# xcodebuild directly, forcing MANUAL signing via command-line build settings
# (highest precedence — overrides the project's Automatic style without editing
# any committed file). All values come from the profile we parsed above.
ARCHIVE="${RUNNER_TEMP:-/tmp}/Runner.xcarchive"
rm -rf "${ARCHIVE}"

# 5a) Prepare Generated.xcconfig (entrypoint + dart-defines) without building.
# --no-codesign is required: even in --config-only mode, `flutter build ios`
# runs its code-signing identity check for a device release build and aborts
# ("No valid code signing certificates were found") before writing the config.
# We only need the config here; signing is handled by the xcodebuild archive
# below. --no-codesign disables that check and does NOT persist any
# signing-disable flag into Generated.xcconfig, so the archive still signs.
flutter build ios --release --config-only --no-codesign \
  -t lib/main_prod.dart \
  --dart-define-from-file=config/prod.json

# 5b) Archive WITHOUT code signing.
# Command-line build settings (KEY=VALUE) apply to EVERY target in the
# workspace, so pinning a PROVISIONING_PROFILE_SPECIFIER here makes the archive
# fail — the framework/library targets (Firebase, GoogleUtilities, plugins,
# Pods) "do not support provisioning profiles". Instead archive unsigned and do
# all signing at the export step below, where the export-options plist scopes
# the profile to the app's bundle id only.
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

# 5c) Export + sign the ad-hoc IPA. -exportArchive re-signs the app and its
# embedded frameworks with the distribution identity from the dedicated
# keychain, using the ad-hoc profile mapped to com.hubmarket.app in EXPORT_PLIST.
mkdir -p build/ios/ipa
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath build/ios/ipa \
  -exportOptionsPlist "${EXPORT_PLIST}"

# 5d) Re-sign Runner.app with the profile's FULL entitlements.
# The archive was built UNSIGNED (CODE_SIGNING_ALLOWED=NO, step 5b), so
# Runner.entitlements (incl. aps-environment) was never embedded — and
# `-exportArchive` only applies the fixed entitlements (application-identifier,
# team, get-task-allow, keychain-access-groups). It DROPS capability
# entitlements like aps-environment, so the app ships with none and APNs
# registration fails: "no valid 'aps-environment' entitlement". Re-signing the
# app with the provisioning profile's own Entitlements dict (which carries
# aps-environment=production) restores it. Only the app bundle is re-signed;
# the export already signed the nested frameworks.
ENTITLEMENTS="${RUNNER_TEMP:-/tmp}/app.entitlements.plist"
/usr/libexec/PlistBuddy -x -c "Print :Entitlements" /dev/stdin <<<"${PROFILE_PLIST}" \
  > "${ENTITLEMENTS}"
# A profile lists some capabilities with a wildcard: Associated Domains is the
# string "*". A signed app has to carry the real list, and the "*" is not a
# value App Store validation accepts. So take the domains from the app's own
# entitlements file, and leave the key out when the app declares none.
AD_KEY="com.apple.developer.associated-domains"
APP_ENT="ios/Runner/Runner.entitlements"
/usr/libexec/PlistBuddy -c "Delete :${AD_KEY}" "${ENTITLEMENTS}" >/dev/null 2>&1 || true
if /usr/libexec/PlistBuddy -c "Print :${AD_KEY}" "${APP_ENT}" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Add :${AD_KEY} array" "${ENTITLEMENTS}"
  i=0
  while domain="$(/usr/libexec/PlistBuddy -c "Print :${AD_KEY}:${i}" "${APP_ENT}" 2>/dev/null)"; do
    /usr/libexec/PlistBuddy -c "Add :${AD_KEY}:${i} string ${domain}" "${ENTITLEMENTS}"
    i=$((i + 1))
  done
fi
# Absolute path — the re-zip below runs after `cd "${RESIGN}"`, so a relative
# build/ios/ipa/… path would resolve under RESIGN and the zip would fail.
IPA="$(ls build/ios/ipa/*.ipa | head -1)"
IPA="$(cd "$(dirname "${IPA}")" && pwd)/$(basename "${IPA}")"
IDENTITY="$(security find-identity -v -p codesigning "${KEYCHAIN}" \
  | grep -oE '[0-9A-F]{40}' | head -1)"
RESIGN="${RUNNER_TEMP:-/tmp}/resign"
rm -rf "${RESIGN}"; mkdir -p "${RESIGN}"
unzip -q "${IPA}" -d "${RESIGN}"
codesign --force --sign "${IDENTITY}" --keychain "${KEYCHAIN}" \
  --entitlements "${ENTITLEMENTS}" "${RESIGN}/Payload/Runner.app"
rm -f "${IPA}"
( cd "${RESIGN}" && zip -qry "${IPA}" Payload )

# Verify the entitlements are actually present now (fail the build otherwise).
EMBEDDED="$(codesign -d --entitlements :- "${RESIGN}/Payload/Runner.app" 2>/dev/null || true)"
if grep -q "aps-environment" <<<"${EMBEDDED}"; then
  echo "✅ aps-environment entitlement embedded"
else
  echo "::error::aps-environment still missing after re-sign"; exit 1
fi

echo "✅ Signed ad-hoc IPA → ${IPA}"
