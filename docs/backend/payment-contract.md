# ZoonZE — Mobile Payment Contract (GraphQL + Native MethodChannel)

> Authoritative contract between the Flutter app and the Magento backend. The app
> already consumes the shapes below (`lib/features/checkout/`) and degrades
> gracefully until they ship: checkout shows "awaiting payment"; the Tabby promo
> hides. App-side design notes: `docs/decisions/payments.md`.

Backend module to create: **`MagentoEgypt_PaymentGraphQl`** (no GraphQL module exists yet).
Gateways in play (already installed): N-Genius (`networkinternational/ngenius`, method `ngeniusonline`)
and Tabby (`tabby/m2-checkout`, methods `tabby_installments`, `tabby_cc_installments`, `tabby_checkout`).

Two GraphQL queries + one Flutter `MethodChannel`:

1. `paymentSession(order_number)` — create / return a gateway session for an **already-placed** order.
2. `tabbyConfig` — Tabby eligibility + promo metadata (NOT checkout gating).
3. `zoonze/payments` MethodChannel — hand the session to the native N-Genius / Tabby SDK and map the result.
4. **Saved cards** — core Magento Vault + two input fields; no new resolver (§④).

**Non-gateway methods need none of the above.** Methods with no off-site step — Magento's
**Zero Subtotal Checkout** (`free`, offered only when the grand total is 0), cash on delivery,
check/money-order — finalise on `placeOrder`. The app detects them as `!isRedirect`
(`PaymentMethodOption`; `free` also flagged `isFree`) and goes straight to order-success with **no**
`paymentSession` call. They still appear in checkout only if `Cart.available_payment_methods` returns
them; the app never injects `free`.

---

## ① `paymentSession(order_number)`

### SDL

> **Confirmed against the live schema (2026-06-26, CI introspection):** the
> deployed `paymentSession` takes **`(order_number, email, lastname, token)`**.
> The guest order-token arg is named **`token`** (not `guest_token`). A guest
> authorizes with **either** the order `token` (`placeOrder.orderV2.token`)
> **or** billing **email + lastname**; a customer sends only `order_number`
> (bearer). The app sends `token` + `email` + `lastname` for guest orders.

```graphql
type Query {
    paymentSession(order_number: String!, email: String, lastname: String, token: String): PaymentSessionOutput
        @resolver(class: "MagentoEgypt\\PaymentGraphQl\\Model\\Resolver\\PaymentSession")
        @doc(description: "Create or return the gateway payment session for an already-placed order (keyed by increment id). Requires the customer/guest who owns the order.")
}

type PaymentSessionOutput {
    order_number: String!
    method_code: String!                 # ngeniusonline | ngeniusonline_applepay | ngeniusonline_samsungpay
                                         # | tabby_installments | tabby_cc_installments | tabby_checkout
    gateway: PaymentGateway!
    status: PaymentSessionStatus!
    payment_id: String                   # Tabby payment.id | N-Genius order reference
    web_url: String                      # URL the native layer drives: N-Genius payment-authorization href, Tabby product web_url
    publishable_key: String              # Tabby public key (native Tabby SDK); null for N-Genius
    additional_data: [PaymentSessionData!]!   # raw gateway passthrough (full order JSON, hrefs, outlet ref, selected product…)
}

type PaymentSessionData {
    key: String!
    value: String
}

enum PaymentGateway {
    NGENIUS
    TABBY
}

enum PaymentSessionStatus {
    READY        # session usable now — app.isReady() == true → launch the native SDK
    PENDING      # session exists but not yet launchable (async gateway state) — app re-queries paymentSession
    REJECTED     # gateway refused to create a session (Tabby pre-score decline) — terminal, app must pick another method
    FAILED       # our-side / transient error creating the session — app may retry
}
```

### Authorization (guest vs logged-in)

A guest places the order without a customer bearer, so it must prove ownership of the order to
reach the gateway. The optional args carry the guest's credentials; the resolver accepts **either**
mechanism:

- **Logged-in customer:** `Authorization: Bearer <token>` is sent; the resolver matches the order
  to the customer and **ignores** the guest args (the app sends only `order_number`).
- **Guest — two interchangeable paths, the app sends both:**
  1. **`guest_token`** — Magento's order token (`placeOrder { orderV2 { token } }`, 2.4.7+). The
     resolver validates it the same way `guestOrderByToken` does.
  2. **`email` + `lastname`** — matched against the order's **billing address** (the classic
     Magento guest-order lookup).
  The resolver authorizes if **either** validates; if neither does → GraphQL authorization error.
  (`placeOrder` must therefore return `orderV2 { number token }` so the app can capture the token.)

### `isReady` contract

The app's `isReady()` is **exactly** `status == READY`. Only `READY` may launch the native SDK.

| status     | app behaviour                                                                 |
|------------|------------------------------------------------------------------------------|
| `READY`    | launch native SDK with `web_url` / `additional_data` (see ③).                |
| `PENDING`  | do **not** launch; re-call `paymentSession(order_number)` (back-off poll).   |
| `REJECTED` | terminal — show "Tabby unavailable for this order", fall back to another method. |
| `FAILED`   | retryable — show generic error + retry.                                       |

### Per-gateway resolver behaviour

**Resolution flow:** load order by `order_number` → assert ownership (logged-in: bearer matches the order's customer; guest: `guest_token` validates **or** `email` + `lastname` match the order's billing address) else GraphQL authorization error → read `order.payment.method` → dispatch to the gateway builder below → normalise to `PaymentSessionOutput`.

#### N-Genius (`ngeniusonline`)

The order endpoint is already hit at place-order time, producing the gateway order with a
`_links.payment.href` and `_embedded.payment[0].state = PENDING_AUTHORIZATION`
(see `NetworkInternational\NGenius\Gateway\Http\Client\PaymentTransaction::postProcess()` and the
`ngenius_networkinternational_sales_order` row: `reference`, `action`, `amount`, `state`, `status`).

The resolver returns that stored N-Genius order (re-fetching the order via the N-Genius order endpoint
if the stored row is stale):

- `gateway` = `NGENIUS`
- `payment_id` = N-Genius **order reference** (`reference`)
- `web_url` = the **payment-authorization href** (`_links.payment.href`, i.e. the `payment-authorization` link)
- `publishable_key` = `null`
- `status`:
  - `READY` when the auth href is present and `state == PENDING_AUTHORIZATION`
  - `PENDING` when the order exists but the auth href / state is not yet present
  - `FAILED` on order endpoint / token error
  - (N-Genius never returns `REJECTED` — pre-auth decline happens inside the SDK, surfaced via ③)
- `additional_data` keys:

  | key                          | value                                                              |
  |------------------------------|--------------------------------------------------------------------|
  | `order_reference`            | `reference`                                                        |
  | `pay_page_href`              | `_links.payment.href` — the hosted pay page (carries `?code=`)      |
  | `authorization_href`         | `_links.payment-authorization.href` — what the SDK authorizes against |
  | `payment_authorization_href` | **DEPRECATED**, misnamed: carries `_links.payment.href`. Kept for app builds ≤ 1.0.0+80 |
  | `outlet_ref`                 | resolved outlet (`outlet_ref` / `outlet_ref_2` per currency)       |
  | `action`                     | `SALE` \| `AUTH` (`ngenius_payment_action`)                        |
  | `state`                      | `PENDING_AUTHORIZATION`                                            |
  | `order_response`             | **full order JSON, stringified** — iOS `NISdk` decodes this whole blob |

#### N-Genius wallets (`ngeniusonline_applepay` / `ngeniusonline_samsungpay`)

Apple Pay and Samsung Pay are **wallet presentations of the N-Genius card flow, not new
gateways**. Both SDKs authorize against the very same N-Genius order the card path uses
(`_links.payment-authorization` + `_links.payment`), so:

- `gateway` stays **`NGENIUS`** — the `PaymentGateway` enum gains **no** value, and the app's
  gateway switch stays two-valued.
- the session payload is **identical to the card one**: same `order_reference`, `pay_page_href`,
  `authorization_href`, `outlet_ref`, `order_response`. `NGeniusSessionBuilder` needs no change.
- only `method_code` differs, and it is what the app maps to `PaymentWallet`.

What the backend must do:

1. **Register the two method codes** so they arrive in `Cart.available_payment_methods` like any
   other method — the app hardcodes nothing and will never inject them. Advertise a wallet code
   only when that wallet is actually enabled on the N-Genius outlet for the store.
2. **Dispatch them in `SessionDispatcher`** alongside `ngeniusonline` (today an unknown method
   throws *"has no mobile payment session"*).
3. **Accept them in `setOrderPaymentMethod.payment_method`.** Without this, switching from card
   to Apple Pay on the complete-payment screen fails after the order is already placed.
4. **Do not gate on device capability.** Whether a handset can actually pay is a device
   question the backend cannot see; the app answers it with `walletAvailability` (§③) and hides
   the rows it cannot honour. The backend advertising a wallet the device lacks is expected and
   harmless.

Outlet enablement is verifiable without a device: call `paymentSession` and look for
`_embedded.payment[0]._links["payment:samsung_pay"]` in `order_response`. If it is absent the
Samsung SDK answers `"Samsung Pay is not enabled"`.

#### Tabby (`tabby_installments` / `tabby_cc_installments` / `tabby_checkout`)

Thin wrapper over the existing `Tabby\Checkout\Model\SessionData::createSession($quote)`, which returns:

```php
[[ "status" => $session->status,                       // "created" | "rejected"
   "payment_id" => $session->payment->id,
   "available_products" => $session->configuration->available_products ]]
```

Mapping:

- `gateway` = `TABBY`
- `payment_id` = `payment_id`
- `publishable_key` = `tabby/tabby_api/public_key` (store-scoped, decrypted)
- `web_url` = the selected product's web_url, picked from `available_products` by the order's method:
  - `tabby_installments` → `available_products.installments[0].web_url`
  - `tabby_checkout` → `available_products.pay_later[0].web_url`
  - `tabby_cc_installments` → `available_products.credit_card_installments[0].web_url`
- `status`:
  - `READY` when `status == "created"` **and** the selected product exists in `available_products`
  - `REJECTED` when `status == "rejected"` (Tabby **pre-score decline**) or the selected product is missing
  - `FAILED` on exception (`createSession` already swallows errors → `['status' => 'rejected']`; resolver may distinguish a thrown error as `FAILED`)
- `additional_data` keys: `merchant_code`, `selected_product` (`installments|pay_later|credit_card_installments`), `web_url`.

> The session must be built from the order's quote. Because `SessionData` reads the request body / checkout
> session, the resolver rebuilds the Tabby `payment` object from the placed order's items/totals rather than
> the live request (so it works headless from the app).

### `setOrderPaymentMethod` — retry / switch method on a placed order

After `placeOrder` the cart is consumed, so a failed/declined/cancelled payment can't be recovered by
re-running checkout. This mutation **changes the payment method on the already-placed order** and returns
a fresh session, powering the app's "Complete payment" screen (pay now with a different method, or pay
later). Same guest auth as `paymentSession` (order token / email + lastname / bearer).

```graphql
type Mutation {
    setOrderPaymentMethod(input: SetOrderPaymentMethodInput!): PaymentSessionOutput
        @resolver(class: "MagentoEgypt\\PaymentGraphQl\\Model\\Resolver\\SetOrderPaymentMethod")
        @doc(description: "Switch the payment method on an already-placed (pending-payment) order and return a fresh gateway session. Same ownership rules as paymentSession.")
}

input SetOrderPaymentMethodInput {
    order_number: String!
    payment_method: String!  # the new method (must be valid for the order/store)
    email: String            # guest auth: order token OR billing email + lastname
    lastname: String
    token: String            # guest order token (placeOrder.orderV2.token)
}
# Live-confirmed inputFields: [email, lastname, order_number, payment_method, token].
# NOTE: the method field is `payment_method` (not `method_code`); PaymentSessionData is {key, value}.
```

- Assert ownership (same as `paymentSession`) → set the order's payment method to `method_code` (the order
  stays in pending-payment; no new order is created) → build + return the gateway session exactly like
  `paymentSession`. Same-method retry doesn't need this — the app just re-calls `paymentSession`.
- Until this mutation is deployed the app degrades to null → it shows "couldn't switch, try again / pay
  later" and the order remains awaiting payment (non-breaking).

---

## ② `tabbyConfig`

Eligibility + promo metadata only. **Checkout availability still flows from
`Cart.available_payment_methods`** (core `Magento\QuoteGraphQl` resolver) — this query never gates placing
an order; it drives Tabby promo widgets and pre-checkout eligibility hints.

### SDL

```graphql
type Query {
    tabbyConfig: TabbyConfigOutput
        @resolver(class: "MagentoEgypt\\PaymentGraphQl\\Model\\Resolver\\TabbyConfig")
        @doc(description: "Tabby eligibility + promo metadata for the current store/currency. Eligibility/promo only — actual checkout availability comes from Cart.available_payment_methods.")
}

type TabbyConfigOutput {
    enabled: Boolean!
    publishable_key: String              # tabby/tabby_api/public_key — native Tabby promo SDK
    merchant_code: String
    currency: String!                    # AED
    products: [TabbyProduct!]!           # one entry per ENABLED product
}

type TabbyProduct {
    type: TabbyProductType!
    method_code: String!                 # tabby_installments | tabby_cc_installments | tabby_checkout
    enabled: Boolean!
    min_amount: Float                    # AED threshold (inclusive)
    max_amount: Float                    # AED threshold (inclusive)
    promo_enabled: Boolean!              # product_promotions / cart_promotions
}

enum TabbyProductType {
    INSTALLMENTS
    PAY_LATER
    CREDIT_CARD_INSTALLMENTS
}
```

### Behaviour

- `enabled` = Tabby active for store (any product enabled, keys configured).
- `currency` = store base currency (`AED`).
- `products[]` = **one entry per enabled product**, thresholds in **AED**.
  - `min_amount` / `max_amount` come from the Tabby pre-score session limits when a cart exists, otherwise
    from store config (`payment/.../promo_min_total`, `promo_limit`) — `null` when Tabby imposes no bound.
  - `promo_enabled` = `product_promotions` (PDP) / `cart_promotions` (cart) config.

### Accepted type-string variants the app normalises → `TabbyProductType`

Tabby's API / config emits several spellings for the same product. The resolver normalises **case-insensitively**:

| `TabbyProductType`         | accepted source strings                                                       | method_code            |
|----------------------------|-------------------------------------------------------------------------------|------------------------|
| `INSTALLMENTS`             | `installments`, `installment`, `pay_in_4`, `split`                             | `tabby_installments`   |
| `PAY_LATER`                | `pay_later`, `paylater`, `pay-later`, `pay_in_14`, `pay later`, `tabby_checkout` | `tabby_checkout`     |
| `CREDIT_CARD_INSTALLMENTS` | `credit_card_installments`, `cc_installments`, `creditcard_installments`, `credit-card-installments` | `tabby_cc_installments` |

---

## ③ Native `MethodChannel` contract

Flutter ⇄ native bridge that launches the gateway SDK once `paymentSession` is `READY`.

- **Channel name:** `zoonze/payments`
- **Method:** `pay`
- **Returns:** `Map<String, dynamic>` with a normalised `status` string (table below). Native invokes the
  gateway SDK, waits for its delegate/callback, and resolves the `MethodChannel` result.

### `pay` argument map

```jsonc
{
  "gateway":      "ngenius" | "tabby",       // wallets keep "ngenius"
  "wallet":       "card" | "applepay" | "samsungpay",
  "methodCode":   "ngeniusonline" | "ngeniusonline_applepay" | "ngeniusonline_samsungpay"
                  | "tabby_installments" | "tabby_cc_installments" | "tabby_checkout",
  "orderNumber":  "2000000123",
  "amount":       199.00,
  "amountString": "199.00",                  // authoritative for Apple Pay — see below
  "currency":     "AED",

  // ---- wallet identifiers (AppConfig, from config/*.json; omitted when blank) ----
  "merchantName":        "Zoonze",           // name shown on the wallet sheet
  "applePayMerchantId":  "merchant.com.zoonze.shop",
  "applePayCountryCode": "AE",
  "applePayNetworks":    ["visa", "mastercard"],
  "samsungPayServiceId": "<32-hex Samsung Pay portal service id>",

  // ---- N-Genius ----
  "orderResponse":             "<full order JSON string from additional_data.order_response>",  // iOS consumes
  "authorizationHref":         "https://.../payment-authorization",   // Android: authorize against this
  "payPageHref":               "https://paypage.../?code=...",        // Android: hosted pay page
  "outletRef":                 "<outlet ref>",

  // ---- Tabby ----
  "webUrl":          "https://checkout.tabby.ai/...",   // both platforms (SDK webview)
  "publishableKey":  "pk_...",
  "paymentId":       "<tabby payment id>"
}
```

**Which field each platform consumes (N-Genius):**

| Platform | SDK entry point                                                                                     | Field consumed                       |
|----------|-----------------------------------------------------------------------------------------------------|--------------------------------------|
| Android  | `PaymentsLauncher.launch(PaymentsRequest.builder().gatewayAuthorizationUrl(auth).payPageUrl(payPage).build())` — `CardPaymentRequest` is deprecated in payment-sdk 5.2.3 | **`orderResponse`** links, falling back to `authorizationHref` + `payPageHref` |
| iOS      | `NISdk.sharedInstance.showCardPaymentViewWith(cardPaymentDelegate:, overParent:, for: order)` where `order: OrderResponse` is decoded from the full order JSON | **`orderResponse`** (full order JSON) |

> Both fields are always sent; each platform ignores the other's. Tabby uses `webUrl` + `publishableKey` +
> `paymentId` on both platforms.

### `walletAvailability` (method 2 on the same channel)

Which wallets **this device** can pay with. No arguments beyond the wallet identifiers above.

```jsonc
{ "applePay": true, "samsungPay": false }
```

- **iOS** answers `PKPaymentAuthorizationController.canMakePayments(usingNetworks:capabilities:)`
  — the network-aware variant, because the bare `canMakePayments()` is true on any capable device
  even with an empty Wallet. `samsungPay` is always `false`.
- **Android** answers the Samsung Pay SDK status (`SPAY_READY`): a Samsung handset, Samsung Wallet
  installed and current, our package + release signature registered in the Samsung Pay portal, and
  a provisioned card. `applePay` is always `false`.
- **Must never throw and must answer within ~1.5s.** A blank identifier short-circuits to `false`
  without touching the SDK (constructing `SamsungPayClient` with a blank service id throws).
- An older native binary that does not implement it yields `MissingPluginException`, which the app
  already treats as "neither available" — so the wallet rows simply stay hidden.

The app uses this only to **filter** the list the API returned; it never adds a method.

### Wallet notes on the `pay` call

- **Apple Pay amount.** `amount` crosses the channel as a double and 199.00 round-trips through
  binary floating point as 199.00000000000003, which PassKit would display *and charge*. Native
  must build its `NSDecimalNumber` from **`amountString`**, never from the double.
- **No new canonical status strings.** A dismissed wallet sheet is `CANCELLED`; an unusable wallet
  (outlet not enabled, Wallet missing, SDK error) is `FAILED` with the detail in `raw`. The
  Samsung SDK reports only success-or-failure, but its failure message embeds the numeric SpaySdk
  code, so `-7` (user cancelled) is recovered; everything else is `FAILED`. Nothing is mapped to
  `DECLINED` — guessing which opaque codes mean "declined" would put wrong copy in front of the
  customer, and both statuses route to the same retry screen anyway.
- **Samsung Pay success is `AUTHORISED`, not `CAPTURED`.** It fires once N-Genius has accepted the
  encrypted token; capture state is unknown, and the app re-queries Magento regardless.
- The wrong-platform wallet (`applepay` on Android, `samsungpay` on iOS) returns `FAILED`, **not**
  `notImplemented` — the latter means "module missing → order awaiting payment", which would be a
  lie. It can only happen through a Dart bug.

### Native status strings → app result

Native normalises each SDK's callback to one canonical `status` string; the app maps as:

| app result  | canonical `status` strings                                  | N-Genius SDK source                                                                 | Tabby SDK source |
|-------------|-------------------------------------------------------------|-------------------------------------------------------------------------------------|------------------|
| **success** | `SUCCESS`, `AUTHORISED`, `CAPTURED`, `PURCHASED`            | iOS `.PaymentAuthorized` / `.PaymentCaptured`; Android `PAYMENT_AUTHORISED` / `PAYMENT_CAPTURED` | `authorized`     |
| **cancelled** | `CANCELLED`, `ABORTED`                                     | iOS `.PaymentAborted`; Android `PAYMENT_ABORTED` / user back                         | `closed`         |
| **declined** | `DECLINED`, `AUTH_FAILED`, `THREE_DS_FAILURE`              | iOS/Android post-auth decline                                                       | `rejected`       |
| **expired** | `EXPIRED`                                                   | —                                                                                   | `expired`        |
| **failed**  | `FAILED`, `ERROR`, *(anything unmapped)*                    | iOS `.PaymentFailed`; Android `PAYMENT_FAILED`; SDK init error                       | SDK/network error |

> N-Genius `.PaymentPostAuthReview` (iOS) / `PAYMENT_POST_AUTH_REVIEW` (Android) → treat as **success**
> (order placed, captured asynchronously). The app should still re-query order status afterwards.

### Result payload

```jsonc
{
  "status": "CAPTURED",          // canonical string from the table above
  "gateway": "ngenius",
  "orderNumber": "2000000123",
  "reference": "<gateway reference / tabby payment id>",
  "raw": "<optional raw SDK status / error message>"
}
```

After any non-`failed` return, the app re-queries the Magento order status (the gateway webhook/return
finalises the order server-side) before showing the success screen.

---

## ④ Saved cards (N-Genius card-on-file)

Lets a customer store the card they paid with and pick it next time. **Read and delete
need no new resolvers** — the app uses core `Magento_VaultGraphQl`, which is already live
on the store. What the backend owes is making N-Genius vault-aware, plus two input fields.

Guests are out of scope: Magento's vault is keyed to a customer.

### What the app already does

`customerPaymentTokens` / `deletePaymentToken` are wired (`AccountQueries.savedCards` /
`deleteSavedCard` → `SavedCard.fromToken`). The whole feature is invisible until the vault
starts returning N-Genius rows: no picker at checkout, no save opt-in accepted, an empty
Account → Payment Methods list. Nothing about today's card flow changes.

### 4.1 Vault rows

Write `vault_payment_token` rows for `ngeniusonline` after a successful authorization, with
`type: card` and the standard Magento card `details` JSON:

```json
{"type":"VI","maskedCC":"1111","expirationDate":"12/2028"}
```

The app filters `customerPaymentTokens` to tokens whose `payment_method_code` contains
`ngenius` (either the base or the vault code is accepted) and tolerates a malformed
`details` blob by rendering a dot-masked card rather than dropping the row.

### 4.2 Saving a card — `is_active_payment_token_enabler`

Mirrors core `BraintreeInput`. Add to the store's schema:

```graphql
input PaymentMethodInput {
    ngeniusonline: NGeniusOnlineInput
    ngeniusonline_vault: VaultTokenInput   # core type, already live: { public_hash: String! }
}

input NGeniusOnlineInput {
    is_active_payment_token_enabler: Boolean
}
```

When the flag is set, create the N-Genius order with tokenisation enabled and persist the
`savedCard` the gateway returns (`cardToken`, `maskedPan`, `expiry`, `scheme`,
`cardholderName`) to the vault once the payment authorizes.

> **The app retries without the flag if the store rejects it**
> (`CheckoutRepository.setPaymentMethod`), and unticks the box. Not saving a card must
> never cost the shopper their order. A *saved-card selection* deliberately does **not**
> fall back — dropping the hash would place the order against an unspecified token.

### 4.3 Paying with a saved card — `ngeniusonline_vault`

A vault method code, mirroring core `payflowpro_cc_vault`. It must arrive from
`Cart.available_payment_methods` like any other method, **only when the customer has at
least one token** — the app hardcodes nothing and never injects it.

```graphql
setPaymentMethodOnCart(input: {
  cart_id: "…"
  payment_method: { code: "ngeniusonline_vault", ngeniusonline_vault: { public_hash: "…" } }
})
```

When the quote payment carries a `public_hash`, the N-Genius order-create payload gains
that token's `savedCard` block. Everything downstream is unchanged: `paymentSession`
returns the same shape, `gateway: NGENIUS`, the same `_links` and `order_response`.

The app does **not** render this as its own row. Checkout folds it into the ordinary card
row and shows the stored cards inside it, so a shopper with four cards still sees one
"Visa & MasterCard" entry (`CheckoutState.visiblePaymentMethods`).

### 4.4 Retrying onto a saved card — `SetOrderPaymentMethodInput.public_hash`

```graphql
input SetOrderPaymentMethodInput {
    public_hash: String   # new, optional: switch a placed order onto a stored card
}
```

Same ownership rules as §①. The app sends a **separate document** when a card is picked
(`CheckoutQueries.setOrderPaymentMethodWithCard`), because an unknown input field fails
document validation even when the variable is null — the existing retry screen must keep
working on a store that hasn't shipped this.

### 4.5 Native: nothing new on the channel

Both SDKs decide the screen from the **order**, not from an argument — so `pay` gains no
field and no CVV ever crosses the channel:

| Platform | Trigger | Entry point |
|---|---|---|
| Android | `savedCard` node in the order JSON | `SavedCardPaymentLauncher.launch(SavedCardPaymentRequest.builder().gatewayAuthorizationUrl(…).payPageUrl(…).build())` — same `PaymentsResult`, so the status mapping is shared |
| iOS | `OrderResponse.savedCard != nil` | `NISdk.launchSavedCardPayment(cardPaymentDelegate:overParent:for:)` (the CVV-less overload) |

CVV recapture is the SDK's own screen (Android `SavedCardPaymentState.CaptureCvv`), which
is what keeps card data out of the app process entirely. An order without a `savedCard`
node falls back to the normal card form — the recoverable direction.

### 4.6 Optional `additional_data`

| key | value |
|---|---|
| `saved_card` | masked pan of the attached card, e.g. `••••1111` — payment-trace/diagnostic only, never load-bearing |

> **Depends on §① actually working.** Saved cards ride the same N-Genius session as the
> card flow, so `docs/backend/ngenius-graphql-session.md` (the checkout-session plugin that
> makes `paymentSession` return `READY` for a GraphQL-placed order) is a hard prerequisite.

---

## Tamara

Redirect gateway, no native SDK. `paymentSession` returns `gateway: TAMARA`,
`status: READY` and a hosted `web_url`; the app opens it and the customer
completes there. Live since 2026-09-28; this section is the backend's own
answer to the app's request on [CL042-DEV42](https://app.clickup.com/t/14zb93nuzft).

### Return URLs

```
{base}tamara/payment/{ORDER_ENTITY_ID}/{success|cancel|failure}
```

- `{ORDER_ENTITY_ID}` is the Magento **entity_id**, not the increment id.
- **Match on the path segment.** Magento reads no query parameters from the
  return, so whatever Tamara appends is ignored — matching on it would mean
  matching on something the store itself does not act on.
- Server-to-server: `tamara/payment/notification?storeId={id}` — never a
  customer return, and must not be read as a verdict.

### `additional_data`

| key | value |
|-----|-------|
| `tamara_order_id` | Tamara's order id |
| `checkout_url` | hosted checkout |
| `success_url` / `cancel_url` / `failure_url` | the three returns above, in full |

Top-level: `payment_id` (the Tamara order id), `web_url`, `publishable_key`.

### The method code is rewritten after payment

Tamara rewrites `tamara_pay_by_instalments` to carry the chosen instalment
count, so the same method comes back as e.g. `tamara_pay_by_instalments_4`.
Everything the app keys on the code (redirect classification, display rank)
matches by substring for this reason; an exact match would sort a paid Tamara
order below Cash on Delivery as an unknown method.

`tamara_pay_now` was **disabled 2026-09-28**: Tamara's live account never
returned `PAY_NOW` for any cart, so every customer who chose it got a failed
payment. Instalments is the only Tamara code served today. Re-enabling is a
config flip once Tamara's account manager enables it properly.

### Open, backend-side

- **Eligibility filtering never runs** (Tamara's `getItems()` early-return), so
  checkout offers Tamara even on carts Tamara declines outright — the customer
  reaches the hosted page and fails there rather than never seeing the option.
  The app cannot fix this: it shows what `available_payment_methods` returns.
- **Base URLs are `http://`**, so the return URLs Tamara receives are `http`.
  It works via redirect, and the app matches the return on **host**, which is
  scheme-independent — but the frontend secure base URL is worth setting.

### Is the success return authoritative?

**Yes — but only if the page is actually loaded.** Magento reconciles with
Tamara synchronously while serving `…/success`.

> **The app must not close the WebView on the redirect.** Intercepting that
> navigation and closing early reports a success the store never recorded. The
> app therefore allows the return to load and closes on `onPageFinished`; a
> success page that fails to load is reported as a failure, not a success.

If the sheet is closed before the page loads, poll the **order state** until it
leaves `pending`/`payment_review`. Do **not** poll
`PaymentSessionOutput.status`: that is session lifecycle, not payment result.

> **App note — `state` is not exposed.** `CustomerOrder` carries `status`, which
> is a **localized label** (the Arabic store view returns Arabic), and no
> `state` field. Deciding whether money moved by matching translated strings is
> not sound, so the app polls for an **invoice** instead: Magento raises one on
> capture, and `invoices` is already in the order selection. It is consulted
> only after a dismissal, can only upgrade the outcome to success, and treats
> any error as not-settled.
>
> **Adding `state` to `CustomerOrder` would let the app follow this guidance
> literally.** Worth doing if Tamara is ever configured authorize-only, where
> no invoice is raised until capture and the probe would find nothing.

## App-side mapping (already implemented)

| Contract | App |
|---|---|
| `paymentSession` SDL | `CheckoutQueries.paymentSession` → `CheckoutRepository.fetchPaymentSession` → `PaymentSession` (`domain/payment_session.dart`) |
| guest auth args (`token` / `email` / `lastname`) | Order `token` from `placeOrder.orderV2.token` (`PlaceOrderResult.orderToken`); billing `email`/`lastname` from `CheckoutState`. `CheckoutController.loadPaymentSession` sends all three for guest orders, none for customers (bearer). Arg is `token`, **not** `guest_token` |
| `isReady == READY` | `PaymentSession.isReady` (`status == ready`) |
| `PENDING` poll | `CheckoutController.loadPaymentSession` (back-off, 4 attempts) |
| post-order recovery | a failed/declined/cancelled payment routes to `CompletePaymentScreen` (pay now / switch method / pay later); driven by the shared `runPaymentSession` |
| `setOrderPaymentMethod` | `CheckoutRepository.setOrderPaymentMethod` — used by `CompletePaymentScreen` when the user picks a *different* method (same method re-calls `paymentSession`) |
| `tabbyConfig` SDL | `CheckoutQueries.tabbyConfig` → `fetchTabbyConfig` → `TabbyConfig` / `TabbyProduct` |
| type-string normalisation | `CheckoutRepository._tabbyType` |
| `zoonze/payments` channel | `NativePaymentGateway` (args + canonical status mapping) |
| status strings | `NativePaymentGateway._mapStatus` (POST_AUTH_REVIEW → success) |
| `wallet` (`pay` arg) | `PaymentSession.wallet` / `walletForMethodCode` (`domain/payment_wallet.dart`) |
| `walletAvailability` | `WalletProbe` / `walletAvailabilityProvider` / `filterUnavailableWallets` (`payments/wallet_availability.dart`) |
| `ngeniusonline_applepay` / `ngeniusonline_samsungpay` | `PaymentMethodOption.isApplePay` / `isSamsungPay`; ordering in `CheckoutController._payRank` |
| `customerPaymentTokens` / `deletePaymentToken` (§④) | `AccountQueries.savedCards` / `deleteSavedCard` → `SavedCard` (`account/domain/saved_card.dart`), `savedCardsProvider` (empty on any error) |
| `is_active_payment_token_enabler` (§4.2) | `CheckoutRepository.setPaymentMethod(saveCard:)` — retries bare if refused; `CheckoutController.setSaveCard` |
| `ngeniusonline_vault` (§4.3) | `PaymentMethodOption.isCardVault`, folded into the card row by `CheckoutState.visiblePaymentMethods`; `SavedCardPicker` |
| `SetOrderPaymentMethodInput.public_hash` (§4.4) | `CheckoutQueries.setOrderPaymentMethodWithCard` → `setOrderPaymentMethod(publicHash:)`, used by `CompletePaymentScreen` |
| order `savedCard` → saved-card SDK screen (§4.5) | `PaymentChannel.hasSavedCard` (Android) / `order.savedCard` (iOS) — no channel argument |
