#!/usr/bin/env bash
# Generate an Apple-compatible Certificate Signing Request (CSR) + private key —
# the exact artifact Keychain Access produces via
#   Keychain Access → Certificate Assistant → Request a Certificate From a
#   Certificate Authority… → "Saved to disk".
#
# This uses openssl, so it runs on macOS AND Linux: you can mint the CSR for an
# Apple Distribution (or Development) certificate WITHOUT a Mac. Apple only reads
# the public key from the CSR, so an openssl-generated request is accepted the
# same as a Keychain one.
#
# What it produces (default: ios/signing/):
#   - <name>.key                 your PRIVATE key — keep it secret, NEVER commit
#                                (gitignored). You need it again to build the .p12.
#   - <name>.certSigningRequest  the CSR to upload to Apple. Safe to share.
#
# Next steps (the script prints these too):
#   1. developer.apple.com → Certificates, Identifiers & Profiles → Certificates
#      → + → "Apple Distribution" (or "Apple Development") → upload the
#      .certSigningRequest → download the resulting .cer.
#   2. Bundle the .cer with the .key from step above into a password-protected
#      .p12 that this project's CI consumes (ios/signing/*.p12 + IOS_P12_PASSWORD):
#        openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM
#        openssl pkcs12 -export -legacy \
#          -inkey ios/signing/<name>.key \
#          -in distribution.pem \
#          -out ios/signing/<name>.p12
#      Use the export password as the GitHub secret IOS_P12_PASSWORD.
#
# Usage:
#   tool/ios_make_csr.sh
#   tool/ios_make_csr.sh --email you@example.com --name "Hub Market" --country AE
#   EMAIL=you@example.com NAME="Hub Market" COUNTRY=AE OUT=ios/signing tool/ios_make_csr.sh
set -euo pipefail

# --- Defaults (override via flags or env) ------------------------------------
EMAIL="${EMAIL:-}"
NAME="${NAME:-Hub Market Shop Distribution}"
COUNTRY="${COUNTRY:-AE}"
OUT="${OUT:-ios/signing}"

# --- Parse flags -------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --email)   EMAIL="$2"; shift 2 ;;
    --name)    NAME="$2"; shift 2 ;;
    --country) COUNTRY="$2"; shift 2 ;;
    --out)     OUT="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "${EMAIL}" ]; then
  echo "::error:: --email (or EMAIL=) is required — use your Apple Developer account email." >&2
  echo "e.g. tool/ios_make_csr.sh --email you@example.com" >&2
  exit 2
fi

command -v openssl >/dev/null || { echo "::error:: openssl not found on PATH." >&2; exit 1; }

# --- Derive a safe filename slug from the common name ------------------------
SLUG="$(printf '%s' "${NAME}" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
SLUG="${SLUG:-apple-distribution}"
mkdir -p "${OUT}"
KEY="${OUT}/${SLUG}.key"
CSR="${OUT}/${SLUG}.certSigningRequest"

if [ -e "${KEY}" ] || [ -e "${CSR}" ]; then
  echo "::error:: ${KEY} or ${CSR} already exists — remove or pass a different --name/--out." >&2
  exit 1
fi

# --- Generate the 2048-bit RSA key + SHA-256 CSR (matches Keychain Access) ----
# Subject: emailAddress / CN / C — Apple uses only the public key, but a complete
# subject keeps the request well-formed.
SUBJ="/emailAddress=${EMAIL}/CN=${NAME}/C=${COUNTRY}"
openssl req -new -newkey rsa:2048 -nodes -sha256 \
  -keyout "${KEY}" \
  -out "${CSR}" \
  -subj "${SUBJ}"

chmod 600 "${KEY}"

echo
echo "✅ CSR generated"
echo "   private key : ${KEY}   (KEEP SECRET — gitignored, do NOT commit)"
echo "   CSR (upload): ${CSR}"
echo
echo "Subject: ${SUBJ}"
echo
echo "Next:"
echo "  1) developer.apple.com → Certificates → + → Apple Distribution →"
echo "     upload ${CSR} → download the .cer."
echo "  2) Make the CI-ready .p12 (set the password as GitHub secret IOS_P12_PASSWORD):"
echo "       openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM"
echo "       openssl pkcs12 -export -legacy -inkey ${KEY} -in distribution.pem -out ${OUT}/${SLUG}.p12"
echo
echo "Verify the CSR any time with:"
echo "  openssl req -in ${CSR} -noout -text"
