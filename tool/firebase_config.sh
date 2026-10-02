#!/usr/bin/env bash
# Writes one platform's Firebase client config (the file FCM needs) from a base64 secret. The repo is
# PUBLIC, so neither file is ever committed (.gitignore lists both): CI decodes it just before the build.
#
#   FIREBASE_ANDROID_CONFIG_BASE64=... bash tool/firebase_config.sh android  # -> android/app/google-services.json
#   FIREBASE_IOS_CONFIG_BASE64=...     bash tool/firebase_config.sh ios      # -> ios/Runner/GoogleService-Info.plist
#
# No secret set: prints a notice and does nothing; the app builds without FCM and push stays off. A secret
# set: the file must parse and belong to this app (package / bundle id com.hubmarket.app, override with
# FIREBASE_APP_ID), otherwise the job fails and nothing is written, so a file of another Firebase project
# can never reach a build. The contents are never printed, only the project id. Guide: docs/release/README.md.
set -euo pipefail

APP_ID="${FIREBASE_APP_ID:-com.hubmarket.app}"
platform="${1:-}"
case "$platform" in
  android)
    secret="${FIREBASE_ANDROID_CONFIG_BASE64:-}"
    secret_name=FIREBASE_ANDROID_CONFIG_BASE64
    dest="android/app/google-services.json"
    ;;
  ios)
    secret="${FIREBASE_IOS_CONFIG_BASE64:-}"
    secret_name=FIREBASE_IOS_CONFIG_BASE64
    dest="ios/Runner/GoogleService-Info.plist"
    ;;
  *)
    echo "usage: bash tool/firebase_config.sh android|ios" >&2
    exit 2
    ;;
esac

if [[ -z "$secret" ]]; then
  echo "::notice::No Firebase $platform config secret ($secret_name): building without FCM, push stays off."
  exit 0
fi

PYTHON="$(command -v python3 || command -v python || true)"
if [[ -z "$PYTHON" ]]; then
  echo "::error::python3 is needed to check the Firebase $platform config."
  exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

if ! printf '%s' "$secret" | base64 --decode > "$tmp" 2>/dev/null || [[ ! -s "$tmp" ]]; then
  echo "::error::$secret_name is not the base64 of a file."
  exit 1
fi

"$PYTHON" - "$platform" "$tmp" "$APP_ID" <<'PY'
import json
import plistlib
import sys

platform, path, app_id = sys.argv[1:4]
try:
    if platform == 'android':
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        project = data['project_info']['project_id']
        ids = [c['client_info']['android_client_info']['package_name'] for c in data['client']]
    else:
        with open(path, 'rb') as f:
            data = plistlib.load(f)
        project = data['PROJECT_ID']
        ids = [data['BUNDLE_ID']]
except Exception as error:
    print('::error::The Firebase %s config does not parse (%s).' % (platform, type(error).__name__))
    sys.exit(1)
if app_id not in ids:
    print('::error::The Firebase %s config is for %s, not %s: the wrong file in the secret?'
          % (platform, ', '.join(ids), app_id))
    sys.exit(1)
print('::notice::Firebase %s config for project %s (%s) written; its contents are not printed.'
      % (platform, project, app_id))
PY

mkdir -p "$(dirname "$dest")"
cp "$tmp" "$dest"
