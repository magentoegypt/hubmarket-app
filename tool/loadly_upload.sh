#!/usr/bin/env bash
# Upload an installable build (.apk / .ipa) to Loadly (https://loadly.io) for
# OTA distribution to testers, then print (and, in CI, publish) the resulting
# install short-link + QR code.
#
#   Usage:  tool/loadly_upload.sh <path-to-.apk-or-.ipa> ["update notes"]
#
#   Env:
#     LOADLY_API_KEY           (required) Loadly account API key. When UNSET the
#                              script prints a warning and exits 0 (skip), so a
#                              pipeline that hasn't wired the secret still passes
#                              — mirrors the keystore/p12 gating in the CI YAML.
#     LOADLY_INSTALL_TYPE      1=public (default) · 2=password · 3=invite-only
#     LOADLY_INSTALL_PASSWORD  install password (used when install type = 2)
#
#   Exit: 0 ok/skipped · 2 bad usage · 4 file missing · 5 upload failed
#
# API: POST https://api.loadly.io/apiv2/app/upload  (multipart/form-data)
#      docs — https://loadly.io/doc/view/api
set -euo pipefail

file="${1:-}"
notes="${2:-}"

if [ -z "$file" ]; then
  echo "usage: $0 <path-to-.apk-or-.ipa> [update-notes]" >&2
  exit 2
fi

# Not configured → skip cleanly (don't fail the build). The secret being present
# is the opt-in switch that turns Loadly distribution on for this repo.
if [ -z "${LOADLY_API_KEY:-}" ]; then
  echo "::warning::LOADLY_API_KEY not set — skipping Loadly upload of $(basename "$file")." >&2
  exit 0
fi

if [ ! -f "$file" ]; then
  echo "error: file not found: $file" >&2
  exit 4
fi

install_type="${LOADLY_INSTALL_TYPE:-1}"
size="$(du -h "$file" | cut -f1)"
echo "Uploading $(basename "$file") ($size) to Loadly…"

# --fail-with-body: non-zero exit on HTTP >=400 but still capture the JSON body.
args=(
  --silent --show-error --fail-with-body
  --max-time 1200
  -X POST "https://api.loadly.io/apiv2/app/upload"
  -F "_api_key=${LOADLY_API_KEY}"
  -F "buildInstallType=${install_type}"
  -F "file=@${file}"
)
[ -n "$notes" ] && args+=(-F "buildUpdateDescription=${notes}")
if [ "$install_type" = "2" ] && [ -n "${LOADLY_INSTALL_PASSWORD:-}" ]; then
  args+=(-F "buildPassword=${LOADLY_INSTALL_PASSWORD}")
fi

resp=""
if ! resp="$(curl "${args[@]}")"; then
  echo "error: Loadly upload request failed (HTTP error)." >&2
  printf '%s\n' "$resp" >&2
  exit 5
fi

# Tolerant parsing: Loadly wraps success as {code:0, data:{…}} but we also accept
# a flat body, and treat buildShortcutUrl as either a short code or a full URL.
jqf() { printf '%s' "$resp" | jq -r "$1 // empty" 2>/dev/null || true; }
code="$(jqf '.code')"
shortcut="$(jqf '.data.buildShortcutUrl // .buildShortcutUrl')"
qrcode="$(jqf '.data.buildQRCodeURL // .buildQRCodeURL')"
name="$(jqf '.data.buildName // .buildName')"
version="$(jqf '.data.buildVersion // .buildVersion')"
message="$(jqf '.message')"

if { [ -n "$code" ] && [ "$code" != "0" ]; } || [ -z "$shortcut" ]; then
  echo "error: Loadly upload rejected${code:+ (code=$code)}${message:+: $message}" >&2
  printf '%s\n' "$resp" | jq . 2>/dev/null || printf '%s\n' "$resp"
  exit 5
fi

case "$shortcut" in
  http://*|https://*) url="$shortcut" ;;
  *)                  url="https://loadly.io/${shortcut}" ;;
esac

echo "✅ Loadly: ${name:-app} ${version} → $url"

# GitHub Actions: expose the link as a step output and on the run summary.
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "url=$url"
    echo "shortcut=$shortcut"
    echo "qrcode=$qrcode"
  } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### 📲 Loadly — ${name:-$(basename "$file")} ${version}"
    echo ""
    echo "- **Install:** [$url]($url)"
    echo "- **File:** \`$(basename "$file")\` ($size)"
    [ -n "$qrcode" ] && { echo ""; echo "<img src=\"$qrcode\" alt=\"QR\" width=\"160\">"; }
  } >> "$GITHUB_STEP_SUMMARY"
fi
