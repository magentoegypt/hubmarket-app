#!/usr/bin/env bash
# Verifies the two files that decide whether a hub-market.magento2.click link opens the APP
# (when installed) instead of the browser:
#
#   Android  https://<host>/.well-known/assetlinks.json
#   iOS      https://<host>/.well-known/apple-app-site-association
#
# Both must be served over https, as application/json, with NO redirect —
# Apple in particular does not follow redirects when fetching the AASA, and
# Magento's store-code rewrite happily 301s /.well-known/... to /uae-en/.
#
# Runs anywhere curl exists (no Mac, no device needed).
#   bash tool/verify_applinks.sh
set -uo pipefail

HOSTS=("${@:-}")
[[ -z "${HOSTS[0]:-}" ]] && HOSTS=(hub-market.magento2.click www.hub-market.magento2.click)

UA="${USER_AGENT:-HubMarketApp/0.1.0 (Flutter)}"
ANDROID_PKG="com.hubmarket.app"
IOS_APPID="544Y9RU66L.com.hubmarket.app"

fail=0
note() { printf '  %-9s %s\n' "$1" "$2"; }

check() { # $1 host, $2 path, $3 label, $4 needle
  local url="https://$1$2" code type body final
  code="$(curl -sS --max-time 25 -H "User-Agent: $UA" -o /dev/null -w '%{http_code}' "$url" 2>/dev/null)"     || { note FAIL "$3: request failed — $url"; fail=1; return; }

  # A 3xx here is fatal, not a detail: Apple does not follow redirects when it
  # fetches the AASA, and Magento's store-code rewrite 301s /.well-known/... to
  # the storefront. Report where it goes so the server fix is obvious.
  if [[ "$code" == 3* ]]; then
    final="$(curl -sS -L --max-time 25 -H "User-Agent: $UA" -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null)"
    note FAIL "$3: HTTP $code -> $final — must be served in place, no redirect"
    fail=1; return
  fi
  if [[ "$code" != "200" ]]; then
    note FAIL "$3: HTTP $code — $url"; fail=1; return
  fi

  type="$(curl -sS --max-time 25 -H "User-Agent: $UA" -o /dev/null -w '%{content_type}' "$url" 2>/dev/null)"
  case "$type" in
    application/json*) ;;
    *) note WARN "$3: Content-Type is '${type:-none}', expected application/json" ;;
  esac

  body="$(curl -sS --max-time 25 -H "User-Agent: $UA" "$url" 2>/dev/null)"
  if ! grep -qF "$4" <<<"$body"; then
    note FAIL "$3: served, but does not name $4"; fail=1; return
  fi
  note OK "$3: 200, no redirect, names $4"
}

for host in "${HOSTS[@]}"; do
  echo "== $host"
  check "$host" "/.well-known/assetlinks.json"              "Android " "$ANDROID_PKG"
  check "$host" "/.well-known/apple-app-site-association"   "iOS     " "$IOS_APPID"
done

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "Some checks failed — links will fall back to the browser on the affected platform."
  exit 1
fi
echo
echo "All good: links open the app when it is installed."
