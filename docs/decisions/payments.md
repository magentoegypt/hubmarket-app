# Decision: Phase 3 payments — native SDK integration

**Status:** Accepted (owner confirmed "a native SDK in phase 3").
**Resolves:** Open Question §2 (payment gateway exposure).
**Scope:** N-Genius (Network International, cards) + Tabby (BNPL: installments / pay later / card installments).

> **Authoritative contract:** `docs/backend/payment-contract.md` (module `MagentoEgypt_PaymentGraphQl`).
> This decision doc is the app-side rationale; where they differ, the contract wins. The Dart side
> already matches the contract field-for-field.

The app integrates both gateways through **native mobile SDKs**, not a hand-rolled
WebView redirect. The Dart side is built and tested now; the native modules, SDK
dependencies, merchant credentials, and the two backend resolvers are the
on-platform steps (they need a device/Xcode build + secrets we don't hold here).

---

## 1. The architecture (in this repo)

A provider-agnostic seam so the screen never talks to an SDK directly:

```
checkout_screen._placeOrder()
  → placeOrder (Magento)                        → order_number
  → CheckoutController.loadPaymentSession()      → PaymentSession (back-off poll while PENDING)
  → _drive(session) routes by status:
      READY     → PaymentGatewayResolver.resolve → NativePaymentGateway (channel zoonze/payments)
                    .present() → PaymentOutcome {success, cancelled, rejected, failed, expired}
                    success → order success; any non-success → CompletePaymentScreen
      PENDING / unavailable / no module → "awaiting payment" screen (no fake UI)
      REJECTED / FAILED (session)       → CompletePaymentScreen
```

The shared `runPaymentSession` (payments/payment_runner.dart) normalises session-status + native
outcome into one result, used by both the initial checkout and the retry screen.

**Non-gateway methods (no SDK, no session).** Methods where `isRedirect == false` skip the whole
session/native path and complete the moment `placeOrder` returns — `_placeOrder` routes them straight
to the order-success screen (`pending: false`). This covers:
- **Zero Subtotal Checkout** (`PaymentMethodOption.isFree`, Magento code **`free`**): surfaced in
  `available_payment_methods` **only when the cart grand total is 0** (fully covered by a coupon or
  100%-off items). It has no gateway — `placeOrder` finalises the order as paid immediately. The
  payment card shows a friendly "no payment needed" subtitle (`checkoutFreeOrder`, EN+AR); there is no
  redirect, no `paymentSession` call, and never a "complete payment" follow-up.
- Cash on delivery, check/money-order, and any other inline method, identically.

As always, the visible method list comes **only** from `cart { available_payment_methods }`, so the
backend decides whether `free` appears — the app never injects it.

**Post-order recovery (CompletePaymentScreen).** Because `placeOrder` consumes the cart *before*
payment, a failed/declined/cancelled/expired attempt can't be recovered by re-running checkout. So
any non-success routes to **CompletePaymentScreen**, which is both:
- **(a) awaiting-payment** — "Order #X is placed and awaiting payment", with an **I'll pay later** exit
  (the order stays pending; payable later), and
- **(b) pay now** — pick a method to retry: the **same** method re-calls `paymentSession`; a **different**
  method calls `setOrderPaymentMethod` (switches the placed order's method) → present again.

Both gateways are driven through the **single native channel** (`zoonze/payments`); the native
module hosts the N-Genius SDK and the Tabby SDK (Tabby's SDK renders its own hosted webview).
There is no Flutter-side WebView redirect engine — it was removed in favour of the native path.

Files: `domain/payment_session.dart` (`PaymentSession`, `PaymentProvider`, `PaymentOutcome`,
`PaymentSessionStatus`), `payments/payment_gateway.dart` (interface + resolver + `PaymentGatewayUnavailable`),
`payments/native_payment_gateway.dart`.

Server-side order-status re-query before showing success is still **mandatory** —
never trust the client return alone (CLAUDE.md §5).

---

## 2. The backend dependency (the real blocker)

Neither extension exposes the SDK session reference to a headless client out of the box:

- **N-Genius** `network-international/ngenius-magento-plugin` (HPP/redirect only): **no
  GraphQL, no client REST.** The order ref / `_links.payment-authorization` are produced
  server-side and consumed by a browser controller. A headless app **cannot** get them
  today → backend work required.
- **Tabby** `tabby-ai/m2-checkout`: exposes the session via **REST**, not GraphQL —
  `POST /V1/guest-carts/:cartId/tabby/session-data/` returns `{ status, payment_id,
  available_products }`. Reachable headlessly, but vendor-shaped.

**Final contract — `paymentSession(order_number)`** (full SDL + per-gateway resolver behaviour
in `docs/backend/payment-contract.md` §①):

```graphql
type PaymentSessionOutput {
  order_number: String!
  method_code: String!            # ngeniusonline | tabby_installments | tabby_cc_installments | tabby_checkout
  gateway: PaymentGateway!        # NGENIUS | TABBY
  status: PaymentSessionStatus!   # READY | PENDING | REJECTED | FAILED
  payment_id: String              # N-Genius order ref · Tabby payment.id
  web_url: String                 # N-Genius payment-authorization href · Tabby product web_url
  publishable_key: String         # Tabby public key (native SDK); null for N-Genius
  additional_data: [PaymentSessionData!]!   # full order JSON, hrefs, outlet ref, selected product…
}
enum PaymentGateway { NGENIUS  TABBY }
enum PaymentSessionStatus { READY  PENDING  REJECTED  FAILED }
```

The query is `paymentSession(order_number: String!, email: String, lastname: String)`. `isReady`
is **exactly** `status == READY`. N-Genius wraps the existing gateway create-order call (returns the
`_links.payment-authorization` href + full order JSON in `additional_data.order_response`); Tabby
wraps `Model\SessionData::createSession()` (returns `payment_id` + `web_url`). The app already
consumes this shape (`checkout_queries.paymentSession`) and **degrades to "awaiting payment" if the
field is absent**, so deploying it is non-breaking.

**Guest orders reach the gateway** via the optional `token` / `email` / `lastname` args: a logged-in
customer is authorized by the bearer (app sends only `order_number`); a guest is authorized by
**either** the Magento order `token` (`placeOrder.orderV2.token`, captured as
`PlaceOrderResult.orderToken`) **or** the billing `email` + `lastname` it entered at checkout. The app
sends all three for guest orders only — the resolver uses whichever validates. _(Live schema confirmed
`paymentSession(order_number, email, lastname, token)` on 2026-06-26 — the guest order-token arg is
named `token`, not `guest_token`.)_

### Tabby config — three products, backend-driven enable + thresholds + promo

Tabby carries three products — **INSTALLMENTS** ("Pay in 4"), **PAY_LATER**, and
**CREDIT_CARD_INSTALLMENTS** — each enabled independently with its own AED thresholds and a
separate `promo_enabled` toggle. **Nothing is hardcoded in the app.** Full SDL + type-string
normalisation in `docs/backend/payment-contract.md` §②:

```graphql
type TabbyConfigOutput {
  enabled: Boolean!
  publishable_key: String
  merchant_code: String
  currency: String!                  # AED
  products: [TabbyProduct!]!         # one entry per ENABLED product
}
type TabbyProduct {
  type: TabbyProductType!            # INSTALLMENTS | PAY_LATER | CREDIT_CARD_INSTALLMENTS
  method_code: String!               # tabby_installments | tabby_cc_installments | tabby_checkout
  enabled: Boolean!
  min_amount: Float                  # inclusive AED bound (null = unbounded)
  max_amount: Float                  # inclusive AED bound (null = unbounded)
  promo_enabled: Boolean!            # product_promotions (PDP) / cart_promotions (cart)
}
```

App side (`domain/tabby_config.dart`, `payments/tabby_promo.dart`):
- `tabbyConfigProvider` (FutureProvider) reads `fetchTabbyConfig()`; null when the resolver
  isn't deployed or Tabby is unconfigured → **promo hidden** (no fabricated eligibility).
- `TabbyProduct.isPromoEligible(price, currency)` gates a promo on enable **+ promo_enabled** +
  currency + min/max; `TabbyConfig.promoFor(price)` returns the promo-eligible products.
- `TabbyPromo(price:)` renders **one line per promo-eligible product** on the **PDP** (under the
  price) and **cart** (under the grand total): "or 4 interest-free payments of AED X" for
  installments (count 4 by Tabby definition), "or pay later, interest-free", "or pay by card in
  instalments". Hidden when none qualify.
- Checkout labels reflect the product too: `PaymentMethodOption.tabbyProduct` (from the method
  code) drives the payment-card subtitle. The method list itself still comes only from
  `cart { available_payment_methods }`, so the backend controls which products appear at checkout.
- The official `tabby_flutter_inapp_sdk` ships `TabbyProductPageSnippet` (a richer, dynamic promo)
  — swap `TabbyPromo` for it once the SDK + publishable key are wired; the config gate stays the
  source of truth either way.

---

## 3. The SDKs (pin versions at integration time)

### Tabby — official Flutter package
- `tabby_flutter_inapp_sdk` (pub.dev, publisher **tabby.ai**, **v2.0.0**, MIT). Renders
  Tabby's hosted session in an embedded WebView with structured callbacks.
- Flow: `await TabbySDK().setup(withApiKey: <publishable key>)` →
  `createSession(TabbyCheckoutPayload(merchantCode:'ae', lang:Lang.en|ar, payment: Payment(amount, Currency.aed, Buyer, order)))`
  → check `session.status` (`created`/`rejected`) → `TabbyWebView.showWebView(context:, webUrl: session.availableProducts.installments.webUrl, onResult:)`.
- `WebViewResult` → our `PaymentOutcome`: `authorized→success`, `rejected→rejected`,
  `expired→expired`, `close→cancelled`. Pre-`created` rejection bounces back **before** the WebView.
- The native module hosts this SDK and is invoked via the `zoonze/payments` channel with the
  Tabby `web_url` + `publishable_key` + `payment_id` from the session — **no secret in the repo**.

### N-Genius — native SDKs + a thin platform channel
- Android `payment-sdk-android` (**v5.0.1**, JitPack: `com.github.network-international.payment-sdk-android:payment-sdk[-core]`), min API 21.
- iOS `NISdk` (**v6.0.1**, CocoaPods), iOS 13+.
- No official Flutter plugin — we own a thin bridge on `MethodChannel('zoonze/payments')`,
  method `pay` (full arg map + result in `docs/backend/payment-contract.md` §③).
  - Android: `PaymentClient(activity).launchCardPayment(CardPaymentRequest.Builder(gatewayUrl = payment-authorization href))`
    → `onActivityResult` → `CardPaymentData.getFromIntent(data)`; `executeThreeDS(...)` when needed.
  - iOS: `NISdk.sharedInstance.showCardPaymentViewWith(...)` with the full order response; conform to
    `CardPaymentDelegate.paymentDidComplete(with:)`.
  - `pay` returns a **result map**; `NativePaymentGateway._mapStatus` maps the canonical `status`
    (`SUCCESS|AUTHORISED|CAPTURED|PURCHASED|POST_AUTH_REVIEW→success`, `CANCELLED|ABORTED|CLOSED→cancelled`,
    `DECLINED|AUTH_FAILED|THREE_DS_FAILURE|REJECTED→rejected`, `EXPIRED→expired`, else `failed`).
- Android consumes `paymentAuthorizationHref` (= `web_url`); iOS consumes `orderResponse`
  (the full order JSON in `additional_data.order_response`).

---

## 4. Sandbox identities (for integration tests)

- **N-Genius** (`api-gateway.sandbox.ngenius-payments.com`): 3DS-success Visa `4012001037141112`
  / `4111111111111111`; decline Visa `4663295942784758` (05). Mastercard success `5200000000000007`.
- **Tabby**: positive flow `otp.success@tabby.ai` + `+9715000000010` (UAE), OTP **8888**;
  background pre-scoring success `id.success@tabby.ai`. Verify the current reject/expiry
  identities against `docs.tabby.ai/testing-guidelines/testing-credentials` (README vs docs disagree).

---

## 4b. Apple Pay + Samsung Pay (CL042-DEV24 / DEV27, 2026-08-20)

### They are wallets, not gateways

Both authorize the **same N-Genius order** the card path already fetches — Samsung's
`startSamsungPay` reads `_links.payment-authorization` and `_links.payment` off the order exactly
as `PaymentsLauncher` does (verified by decompiling `payment-sdk-samsungpay:5.2.3`), and iOS Apple
Pay decodes the same `order_response`. So:

- `PaymentProvider` stays `{ ngenius, tabby }`, `PaymentGatewayResolver.resolve`'s exhaustive
  switch is untouched, and `NGeniusSessionBuilder` needs no backend change. Only `method_code`
  differs (`ngeniusonline_applepay` / `ngeniusonline_samsungpay`, `gateway: NGENIUS`).
- The seam is a new **`wallet` argument** on the existing `pay` call (`card` | `applepay` |
  `samsungpay`), derived from the method code by `walletForMethodCode`.

The one new enum, `PaymentWallet`, is switched on exhaustively in `WalletAvailability.allows`, so a
future wallet is a compile error rather than a silent "unavailable".

### Loose code matching, on purpose

`walletForMethodCode` strips separators and substring-matches. The backend codes are provisional
(nothing is deployed yet), and the failure mode of a miss is severe: an unrecognised wallet code
falls out of `PaymentMethodOption.isRedirect`, and `_placeOrder` then shows **order-success for an
order nobody paid for**. `wallet_payment_method_test.dart` guards that specific case with a code
that contains no `ngenius` substring.

### Availability is a device question the API cannot answer

`available_payment_methods` is a store/cart concern — it will offer Apple Pay to an Android phone.
So the app probes the platform (`walletAvailability`) and *filters* the returned list; it never
adds a method. Two filter points, because `CompletePaymentScreen` is reachable by route with
caller-supplied `extra` and must not trust it. The filter **never empties the list**:
`CheckoutState.shippingDone` requires a non-empty method list, so filtering to nothing would hide
the whole payment step. Failures (module missing, platform error, 3s timeout) all resolve to
"neither available" — hiding a row always beats offering one that dead-ends at the sheet.

### Android is Samsung Pay only

Google Pay was declined by the owner even though `PaymentsRequest.Builder.setGooglePayConfig`
exists on the SDK we already ship. Samsung Pay is a **separate artifact** with a legacy client, and
`payment-sdk-core` had to be declared explicitly because the SDK publishes it in `runtimeElements`
only — without that line `payment.sdk.android.core.Order` is on the runtime classpath but invisible
to the compiler.

Samsung reports only success-xor-failure, but its failure string embeds the numeric SpaySdk code,
so `-7` (user cancelled) is recovered. Nothing maps to `DECLINED`: guessing which opaque codes mean
"declined" would put wrong copy in front of the customer, and both statuses route to the retry
screen anyway. `onSuccess()` reports `AUTHORISED`, not `SUCCESS` — capture state is unknown.

### iOS signing is the real constraint

`tool/ios_*_build.sh` archive **unsigned** and re-sign with the entitlements read out of the
**provisioning profile**, so `ios/Runner/Runner.entitlements` never ships in a CI build. Declaring
the Apple Pay merchant id there does nothing on its own: both committed profiles must be
regenerated with the capability first. `Runner.entitlements` therefore carries the key
**commented out** with the ordered enabling steps, and both build scripts gained a *conditional*
assertion (via PlistBuddy, so the comment cannot trigger it) that fails the build the moment the
file declares the entitlement but the signed app does not carry it.

### Brand marks, not glyphs

Apple's guidelines require the official Apple Pay mark — it may not be recreated, recoloured, or
replaced with a logo glyph, and `Icons.apple` on a payment screen is a plausible App Review flag.
`assets/payments/` holds the drop-in location and a README; until the licensed artwork is added,
`PaymentMethodCard._methodMark` falls back to a neutral Material wallet icon. Row *labels* stay
backend-driven: DEV27's "Visa & MasterCard" is a Magento method-title rename, not app copy.

### Checkout order (DEV27)

`CheckoutController._payRank` now sorts Apple Pay → Samsung Pay → Visa & MasterCard → Tabby → Cash
on Delivery → Check/Money order. The wallet tests must stay above the `ngenius` substring test or
`ngeniusonline_applepay` is swallowed into the card rank. COD remains the pre-selected default despite
moving to the bottom — pre-selecting the first row would arm a wallet sheet nobody asked for.

### Ships dark

With `APPLE_PAY_MERCHANT_ID` / `SAMSUNG_PAY_SERVICE_ID` blank (the default in all three flavours)
and no backend method codes, `walletAvailability` answers both-false, the rows never appear, and
card/COD/Tabby checkout is unchanged. None of the external setup below blocks the rest of the app.
---

## 4c. Wallet methods are live on the API (2026-08-20)

`available_payment_methods` on `eg_en` now returns five methods, in this order:

| code | title |
|---|---|
| `ngeniusonline_applepay` | Apple Pay |
| `ngeniusonline_samsungpay` | Samsung Pay |
| `ngeniusonline` | Visa & MasterCard |
| `tabby_installments` | Pay later with Tabby |
| `cashondelivery` | Cash On Delivery |

`PaymentGateway` is still `{ NGENIUS, TABBY }` and `PaymentSessionOutput` is
unchanged, which is what this design assumed — the wallets are method codes on
the existing gateway, not new gateway values.

**The codes are `ngeniusonline_*`, not the `ngenius_*` this contract originally
assumed.** The loose, separator-normalised matcher in `payment_wallet.dart`
absorbed that without a code change; an exact match would have failed silently,
and the failure mode is the bad one — an unrecognised wallet code falls out of
`isRedirect`, so checkout would skip the payment session and show order-success
for an unpaid order. The live codes are now pinned in
`wallet_payment_method_test.dart` so a future rename fails a test instead.

`_payRank` sorts the live codes to exactly the DEV27 order, verified by
computing the rank of each real code.

**Device behaviour with the wallets live** (Xiaomi, Android 16, prod release,
no merchant id / service id configured): the API returns all five, the app
renders three — Visa & MasterCard, Tabby, COD — with the payment trace reading
`wallets: applePay=false samsungPay=false`. That is the capability filter doing
its job against real API data for the first time; before this the wallets were
never served, so the filter was only exercised by tests.

## 5. Open items before go-live

1. **Build module `MagentoEgypt_PaymentGraphQl`** with the `paymentSession` + `tabbyConfig`
   resolvers (`docs/backend/payment-contract.md` §①–②) — the hard blocker.
2. Implement the native `zoonze/payments` modules (Android `payment-sdk-android`, iOS `NISdk`,
   Tabby SDK) per the channel contract (§③); add SDK deps + merchant credentials (env/secret,
   never committed). Optionally add `tabby_flutter_inapp_sdk` for the richer promo widget.
3. Confirm Tabby checkout visibility comes **only** from `cart { available_payment_methods }`;
   treat mid-flow **reject as a normal return**.
4. Verify exact SDK versions + the live `paymentSession`/`tabbyConfig` shapes against the
   deployed store (`tool/introspect.sh` + a device build).
5. **Apple Pay:** create merchant id `merchant.com.zoonze.shop` (confirm the exact string with
   N-Genius first); get the payment-processing CSR **from N-Genius**, upload it against the
   merchant id and return the certificate to them; enable Apple Pay Payment Processing on the App
   ID; **regenerate both `ios/signing/*.mobileprovision`**; then uncomment the entitlement and set
   `APPLE_PAY_MERCHANT_ID`. Cross-vendor, with real lead time — start it first.
6. **Samsung Pay:** register an *In-App Payment* service (yields the Service ID); register the
   package name — note the flavours produce **three** (`com.zoonze.shop`, `.dev`, `.staging`), so
   register all three or accept prod-only testing; register the **release** signing certificate
   SHA (a debug-signed build gets `-303` and the row simply hides, so Samsung Pay **cannot be
   tested from `flutter run`**); allowlist tester Samsung accounts; get the service approved for
   release; confirm UAE availability. Also confirm the `spay_sdk_api_level` value (2.18 declared)
   on a real Galaxy — a wrong value yields `-10`, which degrades to "unavailable".
7. **N-Genius outlet:** enable Apple Pay and Samsung Pay; confirm the enabled card schemes
   (`SamsungPayCardMapper` maps only VISA / MASTERCARD / AMEX / DISCOVER, and the Apple Pay network
   list is a config value — `PKPaymentNetwork.mada` is the *Saudi* scheme, not a UAE default).
8. **Magento:** register the two wallet method codes, dispatch them in `SessionDispatcher`, accept
   them in `setOrderPaymentMethod`. The DEV27 title rename needs **no Magento
   work at all**: device checkout on 2026-08-20 rendered "Visa & MasterCard" on
   `eg_en` and "بطاقات فيزا وماستركارد" on `eg_ar`, and the app prints
   `method.title` verbatim, so both store views are already renamed.
9. **Verify the NISdk Apple Pay API on the Mac build.** `initiateApplePayWith(applePayDelegate:
   cardPaymentDelegate:for:with:)` and the `ApplePayDelegate` shape could not be checked from the
   Windows dev box (no Pods). A mismatch is contained to `ios/Runner/ApplePaySession.swift` plus
   one call site.

---

## Research provenance (2026)

- Tabby Flutter SDK: pub.dev `tabby_flutter_inapp_sdk` v2.0.0; `github.com/tabby-ai/tabby_flutter_inapp_sdk`; `docs.tabby.ai/api-reference/checkout/create-a-session`.
- Tabby Magento: `github.com/tabby-ai/m2-checkout` (`etc/webapi.xml`, `Model/SessionData.php`), `github.com/tabby-ai/m2-payments`.
- N-Genius SDKs: `github.com/network-international/payment-sdk-android` (v5.0.1; **5.2.3 shipped**, plus `payment-sdk-samsungpay` + `payment-sdk-core` at the same version), `github.com/network-international/payment-sdk-ios` (`NISdk` v6.0.1), `docs.ngenius-payments.com`.
- Samsung Pay: `developer.samsung.com/pay`; SDK 2.22.00 is bundled inside the N-Genius samsungpay AAR. The `SamsungPayClient` / `Order` / `SpaySdk` signatures cited above were read off the AAR bytecode with `javap`, not from documentation.
- N-Genius Magento: `github.com/network-international/ngenius-magento-plugin` (HPP only).
- Magento GraphQL: `developer.adobe.com/commerce/webapi/graphql` (placeOrder/orderV2); community redirect-field pattern (MultiSafepay/Buckaroo/Mollie GraphQL modules, graphcommerce.org, scandipwa docs).
