#!/usr/bin/env bash
#
# Verify the live `MagentoEgypt_PaymentGraphQl` module against what the Flutter
# app actually sends/expects (docs/backend/payment-contract.md). Run this from a
# network that can reach hub-market.magento2.click — the CI/build env is egress-blocked (403).
#
# It prints: (1) the resolver arg/field/enum shapes, (2) a live `tabbyConfig`,
# and (3) a live `paymentSession` for a real placed order (guest or customer).
# Paste the whole output back and I'll diff it against the app field-by-field.
#
# Usage:
#   # A) Schema shape only (no order needed):
#   bash tool/verify_payments.sh
#
#   # B) Live session for a placed GUEST order (email+lastname OR the order token):
#   ORDER_NUMBER=000000123 EMAIL=buyer@example.com LASTNAME=Khan bash tool/verify_payments.sh
#   ORDER_NUMBER=000000123 GUEST_TOKEN=<orderV2.token> bash tool/verify_payments.sh
#
#   # C) Live session for a LOGGED-IN customer order (bearer token):
#   ORDER_NUMBER=000000123 TOKEN=<customer_token> bash tool/verify_payments.sh
#
#   # Override the store view / endpoint if needed:
#   STORE=eg_ar ENDPOINT=https://hub-market.magento2.click/graphql bash tool/verify_payments.sh
set -euo pipefail

ENDPOINT="${ENDPOINT:-https://hub-market.magento2.click/graphql}"
# Default to NO Store header (default view) — an unknown code makes Magento
# reject the whole request with "Requested store is not found". Set STORE=<code>
# (from `tool/introspect.sh`) only to target a specific view.
STORE="${STORE:-}"
UA="${USER_AGENT:-HubMarketApp/0.1.0 (Flutter)}"

post() { # $1 = json body
  local auth=() hdr=()
  [ -n "${TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${TOKEN}")
  [ -n "${STORE:-}" ] && hdr=(-H "Store: ${STORE}")
  curl -sS --max-time 40 -X POST "$ENDPOINT" \
    -H "Content-Type: application/json" \
    "${hdr[@]}" \
    -H "User-Agent: $UA" \
    "${auth[@]}" \
    --data "$1"
}
jval() { if [ -n "${1:-}" ]; then printf '"%s"' "$1"; else printf 'null'; fi; }

echo "ENDPOINT=$ENDPOINT  STORE=$STORE"
echo "============================================================"
echo "1) Resolver ARG shapes — paymentSession / setOrderPaymentMethod / tabbyConfig"
echo "   (app needs: paymentSession(order_number!, email, lastname, guest_token))"
echo "------------------------------------------------------------"
for parent in Query Mutation; do
  post "{\"query\":\"{ __type(name:\\\"$parent\\\"){ fields{ name args{ name type{ kind name ofType{ kind name } } } } } }\"}" \
    | tr '{' '\n' | grep -iE '"name": ?"(paymentSession|setOrderPaymentMethod|tabbyConfig)"' -A30 \
    || echo "  (none of the payment resolvers found on $parent — module not deployed on this store?)"
done
echo

echo "============================================================"
echo "2) TYPE + ENUM shapes the app parses"
echo "   PaymentSessionOutput.additional_data MUST be a [{key,value}] list."
echo "   gateway ∈ {NGENIUS,TABBY}; status ∈ {READY,PENDING,REJECTED,FAILED}."
echo "------------------------------------------------------------"
for t in PaymentSessionOutput PaymentSessionData PaymentGateway PaymentSessionStatus \
         TabbyConfigOutput TabbyProduct TabbyProductType; do
  echo "-- $t --"
  post "{\"query\":\"{ __type(name:\\\"$t\\\"){ name kind fields{ name type{ kind name ofType{ kind name ofType{ kind name } } } } enumValues{ name } } }\"}"
  echo
done

echo "============================================================"
echo "3) LIVE tabbyConfig (enable flags + thresholds + promo + keys)"
echo "------------------------------------------------------------"
post '{"query":"{ tabbyConfig { enabled publishable_key merchant_code currency products { type method_code enabled min_amount max_amount promo_enabled } } }"}'
echo; echo

if [ -n "${ORDER_NUMBER:-}" ]; then
  echo "============================================================"
  echo "4) LIVE paymentSession for order ${ORDER_NUMBER}"
  echo "   auth: ${TOKEN:+bearer}${EMAIL:+ email+lastname}${GUEST_TOKEN:+ guest_token}"
  echo "------------------------------------------------------------"
  VARS=$(printf '{"o":"%s","e":%s,"l":%s,"g":%s}' \
    "$ORDER_NUMBER" "$(jval "${EMAIL:-}")" "$(jval "${LASTNAME:-}")" "$(jval "${GUEST_TOKEN:-}")")
  post "{\"query\":\"query(\$o:String!,\$e:String,\$l:String,\$g:String){ paymentSession(order_number:\$o,email:\$e,lastname:\$l,guest_token:\$g){ order_number method_code gateway status payment_id web_url publishable_key additional_data{ key value } } }\",\"variables\":$VARS}"
  echo; echo
  echo "Expected for N-Genius: additional_data carries the keys"
  echo "  order_response (full order JSON), payment_authorization_href, outlet_ref."
  echo "Expected for Tabby: payment_id + web_url + publishable_key populated."
else
  echo "(Skipping live paymentSession — set ORDER_NUMBER=… plus auth to include section 4.)"
fi
echo
echo "Done. Paste the full output back for a field-by-field diff against the app."
