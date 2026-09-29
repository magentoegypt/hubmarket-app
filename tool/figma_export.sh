#!/usr/bin/env bash
#
# Export every Hub Market app screen from Figma as a PNG into docs/figma/.
#
# The agent/build sandbox can't reach figma.com (egress policy blocks it, like
# hub-market.magento2.click), so this runs in CI (.github/workflows/figma-export.yml) or on a
# dev machine that can reach api.figma.com.
#
# Requires:
#   FIGMA_TOKEN     a Figma personal access token (Settings → Account →
#                   Personal access tokens). In CI it's the FIGMA_TOKEN secret.
# Optional:
#   FIGMA_FILE_KEY  defaults to the Hub Market design file.
#   FIGMA_SCALE     export scale (default 2).
set -euo pipefail

FILE_KEY="${FIGMA_FILE_KEY:-lxyvR0z3xERp8lw8IlPTlH}"
: "${FIGMA_TOKEN:?set FIGMA_TOKEN (a Figma personal access token)}"
SCALE="${FIGMA_SCALE:-2}"
OUT="docs/figma"
mkdir -p "$OUT"

# EN screen frames — "<nodeId>|<slug>". Keep in sync with docs/figma/README.md.
SCREENS=(
  "52:2|01-splash-launch"
  "54:2|02-splash-welcome"
  "59:2|03-sign-in"
  "59:49|04-sign-up"
  "60:29|05-forgot-password"
  "2:2|06-home"
  "178:2|07-menu-drawer"
  "57:2|08-categories"
  "58:2|09-search"
  "58:78|10-search-results"
  "68:2|11-filters-sheet"
  "32:2|12-plp-fragrance"
  "34:2|13-pdp"
  "55:2|14-wishlist"
  "38:2|15-cart"
  "66:70|16-cart-empty"
  "40:2|17-checkout"
  "60:51|18-order-success"
  "62:2|19-my-orders"
  "63:2|20-order-tracking"
  "42:2|21-my-account"
  "64:2|22-saved-addresses"
  "40:9|23-add-address"
  "65:53|24-notifications"
  "66:2|25-help-faq"
  "111:2|26-edit-profile"
  "420:2|27-brands"
)

# One images API call returns a render URL per node id.
ids=$(IFS=,; echo "${SCREENS[*]%%|*}")
echo "Requesting ${#SCREENS[@]} screen renders from Figma ($FILE_KEY)…"
resp="$(curl -sS -H "X-Figma-Token: ${FIGMA_TOKEN}" \
  "https://api.figma.com/v1/images/${FILE_KEY}?ids=${ids}&format=png&scale=${SCALE}")"

err="$(echo "$resp" | jq -r '.err // empty')"
[ -z "$err" ] || { echo "::error::Figma API error: $err"; exit 1; }

fail=0
for entry in "${SCREENS[@]}"; do
  node="${entry%%|*}"
  slug="${entry##*|}"
  url="$(echo "$resp" | jq -r --arg id "$node" '.images[$id] // empty')"
  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "  ! no render for $node ($slug)"; fail=1; continue
  fi
  curl -sS -o "${OUT}/${slug}.png" "$url"
  echo "  ✓ ${slug}.png"
done

echo "Done → ${OUT}/"
exit $fail
