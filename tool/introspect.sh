#!/usr/bin/env bash
#
# Introspect the live Magento GraphQL endpoint to (1) confirm store views and
# per-view config, and (2) emit a schema file for Phase 1 graphql_codegen.
#
# Run this from a network that can reach hub-market.magento2.click (the CI/build environment is
# blocked by the org egress policy).
#
# Usage:
#   bash tool/introspect.sh
#   ENDPOINT=https://hub-market.magento2.click/graphql STORE_EN=eg_en STORE_AR=eg_ar bash tool/introspect.sh
#
set -euo pipefail

ENDPOINT="${ENDPOINT:-https://hub-market.magento2.click/graphql}"
STORE_EN="${STORE_EN:-eg_en}"
STORE_AR="${STORE_AR:-eg_ar}"
UA="${USER_AGENT:-HubMarketApp/0.1.0 (Flutter)}"
OUT_DIR="lib/core/graphql"
mkdir -p "$OUT_DIR"

post() { # $1 = Store header (empty => omit, use default store), $2 = json body
  local hdr=() auth=()
  [ -n "$1" ] && hdr=(-H "Store: $1")
  # Optional bearer (e.g. TOKEN from a CI secret). Not needed for the public
  # availableStores/storeConfig/introspection calls, but forwarded if present.
  [ -n "${TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${TOKEN}")
  curl -sS --max-time 40 -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    "${hdr[@]}" \
    "${auth[@]}" \
    -H "User-Agent: $UA" \
    --data "$2"
}

# availableStores is store-agnostic. Query it with NO `Store` header so Magento
# answers from the DEFAULT view — sending an unknown code (e.g. the provisional
# uae-en) makes Magento reject the whole request with "Requested store is not
# found", which would also block discovery. The codes printed here are the
# authoritative source for STORE_EN / STORE_AR below.
echo "== availableStores (no Store header → default view) =="
echo "   >>> Read the store_code values below; they are the REAL codes. <<<"
post "" '{"query":"{ availableStores(useCurrentGroup:false){ store_code store_name locale is_default_store base_currency_code default_display_currency_code base_url secure_base_url base_media_url } }"}'
echo; echo
echo "== storeConfig (no Store header → default view, shows the default store_code) =="
post "" '{"query":"{ storeConfig { store_code store_name locale base_currency_code default_display_currency_code base_url secure_base_url base_media_url } }"}'
echo; echo
echo "Now re-run with the discovered codes for the per-view + payment sections, e.g.:"
echo "   STORE_EN=<en_code> STORE_AR=<ar_code> bash tool/introspect.sh"
echo

for store in "$STORE_EN" "$STORE_AR"; do
  echo "== storeConfig (Store: $store) =="
  post "$store" '{"query":"{ storeConfig { store_code store_name locale base_currency_code default_display_currency_code base_url secure_base_url base_media_url } }"}'
  echo; echo
done

echo "== Phase 1 catalog smoke (Store: $STORE_EN) — the app's home queries =="
# categoryList drives the home/menu; this is the first query the app runs.
# Watch for GraphQL "errors" AND the include_in_menu value type (Int vs Boolean).
echo "-- categoryList --"
post "$STORE_EN" '{"query":"{ categoryList { uid name url_key children { uid name url_key image include_in_menu product_count } } }"}'
echo; echo
echo "-- products(search) --"
post "$STORE_EN" '{"query":"query($s:String){ products(search:$s, pageSize:3, currentPage:1){ total_count items{ sku name url_key stock_status image{ url } price_range{ minimum_price{ final_price{ value currency } } } } } }","variables":{"s":"a"}}'
echo; echo

echo "== StoreConfig fields — confirm the home banner / offer field names =="
# The app reads the admin announcement message + Special Offer Banner from
# storeConfig (lib/features/catalog/data/special_offer_provider.dart). Print the
# real StoreConfig field names so the queries can match the module's schema.
post "" '{"query":"{ __type(name:\"StoreConfig\"){ fields{ name } } }"}' \
  | tr ',' '\n' | grep -iE 'offer|coupon|special|banner|announcement|message|magentoegypt' \
  || echo "  (no announcement/offer fields on StoreConfig — module not deployed yet?)"
echo

echo "== Phase 3 payment contract — MagentoEgypt_PaymentGraphQl (no Store header) =="
# Schema introspection is store-agnostic, so it works without a valid code.
# Confirm the resolvers + args exist on the live schema and match the app's queries
# (docs/backend/payment-contract.md). paymentSession must accept
# order_number!, email, lastname, guest_token; tabbyConfig must exist.
post "" '{"query":"{ __type(name:\"Query\"){ fields(includeDeprecated:true){ name args{ name type{ kind name ofType{ kind name } } } } } }"}' \
  | tr ',' '\n' | grep -A12 -iE '"name": ?"(paymentSession|tabbyConfig)"' || \
  echo "  (paymentSession/tabbyConfig not found on Query — module not deployed?)"
echo
for t in PaymentSessionOutput TabbyConfigOutput TabbyProduct; do
  echo "-- type $t --"
  post "" "{\"query\":\"{ __type(name:\\\"$t\\\"){ name kind fields{ name type{ kind name ofType{ kind name } } } enumValues{ name } } }\"}"
  echo
done
echo "Cross-check the above field/arg/enum names against docs/backend/payment-contract.md."
echo

echo "== Definitive arg + enum check (python3, no Store header) =="
# Clean, unambiguous output: confirms paymentSession / setOrderPaymentMethod arg
# names (esp. whether guest_token exists) and the three enum value sets.
python3 - "$ENDPOINT" "${TOKEN:-}" "$UA" <<'PY' || echo "  (python3 unavailable or request failed)"
import json, sys, urllib.request
endpoint, token, ua = sys.argv[1], sys.argv[2], sys.argv[3]
def q(query):
    data = json.dumps({"query": query}).encode()
    req = urllib.request.Request(endpoint, data=data,
        headers={"Content-Type": "application/json", "User-Agent": ua})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    return json.load(urllib.request.urlopen(req, timeout=40))
for parent in ("Query", "Mutation"):
    r = q('{ __type(name:"%s"){ fields{ name args{ name } } } }' % parent)
    fields = ((r.get("data") or {}).get("__type") or {}).get("fields") or []
    for f in fields:
        if f["name"] in ("paymentSession", "setOrderPaymentMethod", "tabbyConfig"):
            print("  %s.%s args: %s" % (parent, f["name"], [a["name"] for a in f["args"]]))
for t in ("PaymentGateway", "PaymentSessionStatus", "TabbyProductType"):
    r = q('{ __type(name:"%s"){ enumValues{ name } } }' % t)
    ty = (r.get("data") or {}).get("__type")
    vals = [e["name"] for e in (ty.get("enumValues") or [])] if ty else None
    print("  enum %s: %s" % (t, vals))
# Object/input shapes the app selects on: additional_data element ({key,value}?)
# and the setOrderPaymentMethod input fields.
for t in ("PaymentSessionData", "SetOrderPaymentMethodInput"):
    r = q('{ __type(name:"%s"){ kind fields{ name } inputFields{ name } } }' % t)
    ty = (r.get("data") or {}).get("__type")
    if ty:
        fields = [x["name"] for x in (ty.get("fields") or [])]
        inputs = [x["name"] for x in (ty.get("inputFields") or [])]
        print("  %s: kind=%s fields=%s inputFields=%s"
              % (t, ty.get("kind"), fields or None, inputs or None))
    else:
        print("  %s: (type not found — element name may differ)" % t)
PY
echo

echo "== Full schema introspection -> $OUT_DIR/schema.graphql (SDL) or schema.json =="
# Prefer SDL via a tool if available; otherwise dump the introspection JSON.
# Store-agnostic → no header needed.
INTROSPECTION_QUERY='{"query":"query IntrospectionQuery { __schema { queryType { name } mutationType { name } subscriptionType { name } types { ...FullType } directives { name locations args { ...InputValue } } } } fragment FullType on __Type { kind name description fields(includeDeprecated:true){ name description args{ ...InputValue } type{ ...TypeRef } isDeprecated deprecationReason } inputFields{ ...InputValue } interfaces{ ...TypeRef } enumValues(includeDeprecated:true){ name description isDeprecated deprecationReason } possibleTypes{ ...TypeRef } } fragment InputValue on __InputValue { name description type{ ...TypeRef } defaultValue } fragment TypeRef on __Type { kind name ofType{ kind name ofType{ kind name ofType{ kind name ofType{ kind name ofType{ kind name ofType{ kind name ofType{ kind name } } } } } } } }"}'
post "" "$INTROSPECTION_QUERY" > "$OUT_DIR/schema.introspection.json"
echo "Wrote $OUT_DIR/schema.introspection.json"

# Convert the introspection JSON to SDL for graphql_codegen. Needs Node + the
# `graphql` npm package (introspect.yml installs it; locally: `npm i graphql`).
if command -v node >/dev/null 2>&1 && node -e "require.resolve('graphql')" >/dev/null 2>&1; then
  node tool/json_to_sdl.mjs "$OUT_DIR/schema.introspection.json" "$OUT_DIR/schema.graphql"
else
  echo "SDL: install once with \`npm i graphql\`, then:"
  echo "     node tool/json_to_sdl.mjs $OUT_DIR/schema.introspection.json $OUT_DIR/schema.graphql"
fi
echo
echo "Next: update docs/decisions/stores.md + config/*.json with the confirmed codes,"
echo "      then \`dart run build_runner build\` to (re)generate typed GraphQL Dart."
