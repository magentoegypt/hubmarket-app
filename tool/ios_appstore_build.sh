#!/usr/bin/env bash
# Build a SIGNED App Store IPA from the Apple Distribution cert (.p12) + the
# App Store provisioning profile in ios/signing/ — no fastlane `match`, no
# separate signing repo. macOS only. ios/signing/ is git-ignored (the repo is
# public): release-ios.yml decodes the files there from secrets; locally, copy
# them in by hand.
#
# This mirrors tool/ios_sign_build.sh (the ad-hoc path). The only differences:
#   - export `method` is `app-store` (not `ad-hoc`);
#   - it selects the App Store profile — the .mobileprovision WITHOUT a
#     `ProvisionedDevices` list (that key marks ad-hoc/development profiles).
#
# Required:
#   - ios/signing/*.p12              Apple Distribution cert exported WITH its
#                                    private key, protected by a password
#   - ios/signing/*.mobileprovision  an App Store (STORE) profile for the app id
#   - env IOS_P12_PASSWORD           the password that protects the .p12
#
# Output: build/ios/ipa/*.ipa — ready for `fastlane beta` (upload_to_testflight).
set -euo pipefail

SIGN_DIR="ios/signing"
P12="$(ls "${SIGN_DIR}"/*.p12 2>/dev/null | head -1 || true)"
: "${IOS_P12_PASSWORD:?IOS_P12_PASSWORD is required}"
[ -n "${P12}" ] || { echo "::error::No .p12 found in ${SIGN_DIR}"; exit 1; }

# Select the App Store profile: pick the first .mobileprovision whose decoded
# plist has NO `ProvisionedDevices` key (ad-hoc/dev profiles list device UDIDs;
# App Store profiles never do). This is what tells the App Store profile apart
# from an ad-hoc one lying next to it.
PROFILE=""
for p in "${SIGN_DIR}"/*.mobileprovision; do
  [ -e "$p" ] || continue
  if ! security cms -D -i "$p" 2>/dev/null | grep -q "ProvisionedDevices"; then
    PROFILE="$p"; break
  fi
done
[ -n "${PROFILE}" ] || { echo "::error::No App Store profile (one without ProvisionedDevices) found in ${SIGN_DIR}"; exit 1; }
echo "Cert: ${P12}"
echo "App Store profile: ${PROFILE}"

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

# 4) Generate ExportOptions for manual App Store signing from the real values.
EXPORT_PLIST="${RUNNER_TEMP:-/tmp}/ExportOptions-AppStore.plist"
cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>provisioningProfiles</key><dict>
    <key>${BUNDLE_ID}</key><string>${PROFILE_NAME}</string>
  </dict>
  <key>uploadSymbols</key><true/>
</dict></plist>
PLIST

# 5) Build the signed IPA.
#
# As in the ad-hoc path, we deliberately do NOT use `flutter build ipa`: its
# `xcodebuild archive` phase uses the project's CODE_SIGN_STYLE=Automatic, which
# can't provision on a CI runner with no Apple ID ("No development certificates
# available"). Instead: generate the Flutter build config, archive UNSIGNED, then
# export + sign with the manual App Store profile.
ARCHIVE="${RUNNER_TEMP:-/tmp}/Runner.xcarchive"
rm -rf "${ARCHIVE}"

# 5a) Prepare Generated.xcconfig (entrypoint + dart-defines) without building.
flutter build ios --release --config-only --no-codesign \
  -t lib/main_prod.dart \
  --dart-define-from-file=config/prod.json \
  ${BUILD_NUMBER:+--build-number="${BUILD_NUMBER}"}

# 5b) Archive WITHOUT code signing (framework/plugin targets can't take a
# provisioning profile; sign only the app bundle, at the export step).
xcodebuild archive \
  -workspace ios/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE}" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO

# 5c) Export + sign the App Store IPA. -exportArchive re-signs the app and its
# embedded frameworks with the distribution identity from the dedicated keychain,
# using the App Store profile mapped to com.hubmarket.app in EXPORT_PLIST.
mkdir -p build/ios/ipa
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportPath build/ios/ipa \
  -exportOptionsPlist "${EXPORT_PLIST}"

# 5d) Re-sign Runner.app with the profile's FULL entitlements.
# The archive was built UNSIGNED (step 5b), so capability entitlements like
# aps-environment were never embedded, and -exportArchive applies only the fixed
# ones — so the app would ship WITHOUT aps-environment and APNs registration
# would fail. Re-sign the app bundle with the profile's own Entitlements dict
# (which carries aps-environment=production) to restore it. Only the app bundle
# is re-signed; the export already signed the nested frameworks.
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
# Re-zip ALL top-level entries the export produced (Payload/, and any Symbols/ or
# SwiftSupport/) — not just Payload — so App Store validation keeps everything it
# expects. Absolute IPA path because we cd into RESIGN first.
( cd "${RESIGN}" && zip -qry "${IPA}" . )

# Verify the entitlements are actually present now (fail the build otherwise).
EMBEDDED="$(codesign -d --entitlements :- "${RESIGN}/Payload/Runner.app" 2>/dev/null || true)"
if grep -q "aps-environment" <<<"${EMBEDDED}"; then
  echo "✅ aps-environment entitlement embedded"
else
  echo "::error::aps-environment still missing after re-sign"; exit 1
fi

# Universal links. Conditional on purpose: the entitlements we sign with come
# from the PROVISIONING PROFILE, not from ios/Runner/Runner.entitlements, so
# declaring Associated Domains in that file does nothing on its own — the
# profile has to be regenerated with the capability. This catches exactly that
# drift, and stays silent until the key is declared. PlistBuddy (not grep) so
# the commented-out runbook in Runner.entitlements cannot trigger it — only a
# real, parsed key counts. It matters because the failure is INVISIBLE: without
# the entitlement the app still installs and runs, hub-market.magento2.click
# links just keep opening Safari.
ENT_FILE="ios/Runner/Runner.entitlements"
if /usr/libexec/PlistBuddy -c "Print :com.apple.developer.associated-domains" "${ENT_FILE}" >/dev/null 2>&1; then
  if grep -q "associated-domains" <<<"${EMBEDDED}"; then
    echo "✅ Associated Domains entitlement embedded"
  else
    echo "::error::Runner.entitlements declares com.apple.developer.associated-domains but the signed app does not carry it — regenerate the App Store profile (secret IOS_APPSTORE_PROFILE_BASE64) with Associated Domains enabled on the App ID"
    exit 1
  fi
fi

echo "✅ Signed App Store IPA → ${IPA}"
