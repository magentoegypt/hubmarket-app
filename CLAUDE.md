# CLAUDE.md — Zoonze Mobile App (Flutter)

> **Mission:** Build a production-grade Flutter app (Android + iOS) that is a headless storefront client for **zoonze.com**, running on **Magento Open Source 2.4.8-p5**. UAE market, **bilingual** — English (LTR) + Arabic (RTL), **AED** currency.

This file is the working context for Claude Code. Read it fully before scaffolding. Resolve everything under **Open Questions** with the owner before writing checkout/payment code.

---

## 1. Context snapshot

| Item | Value |
|---|---|
| Backend | Magento Open Source **2.4.8-p5** at `https://zoonze.com/` |
| API layer | **GraphQL** (`https://zoonze.com/graphql`) — primary. REST (`/rest/...`) only as fallback. |
| Market | **UAE** |
| Store views | **Two** — English: `https://zoonze.com/uae-en/` (LTR) · Arabic: `https://zoonze.com/uae-ar/` (RTL). Both supported from launch. |
| Store codes | Likely `uae-en` / `uae-ar` (or `uae_en` / `uae_ar`). **Confirm exact codes via `availableStores` — see §3.3.** Default view: **TBD**. |
| Currency | **AED** (verify per store via `storeConfig`) |
| Edge | AWS CloudFront CDN + AWS WAF in front of an Apache2 origin (`origin.zoonze.com`) |
| Payment gateways | **N-Genius** (Network International — card/HPP) + **Tabby** (BNPL, "Pay in 4" interest-free installments) — both via Magento extensions |
| App platforms | Android + iOS, single codebase |

The app is a **client** of Magento. It does **not** contain Magento PHP. All catalog, cart, checkout, customer, and order logic is delegated to Magento's GraphQL schema. Treat the schema as the contract; introspect the live endpoint rather than guessing fields.

---

## 2. Tech stack (decided — pin exact versions at `pub add` time)

These are committed choices so you don't have to deliberate. They're swappable only if the owner overrides.

- **Flutter** — latest stable 3.x, Dart 3.x, null-safe.
- **State management** — **Riverpod 2.x** (`flutter_riverpod` + `riverpod_annotation` + `riverpod_generator`). This also serves as DI; do not add `get_it` unless a need appears.
- **GraphQL client** — **`graphql_flutter`** (mature, normalized cache, links). Add **`graphql_codegen`** to generate typed Dart classes from `.graphql` operation files — do **not** hand-write `Map<String,dynamic>` parsing for core flows.
- **Routing** — **`go_router`** (declarative, deep-link ready for push + N-Genius return URLs).
- **Secure storage** — **`flutter_secure_storage`** (customer token, never in shared_preferences).
- **Local persistence** — `shared_preferences` (flags, locale, selected store) + `hive_ce` (offline cart snapshot, wishlist cache, recently viewed).
- **HTTP (non-GraphQL)** — **`dio`** (N-Genius callbacks, file/image edge cases, health checks).
- **In-app browser** — **`flutter_inappwebview`** (N-Genius hosted payment page + redirect interception).
- **Images** — `cached_network_image`.
- **Localization** — Flutter `gen-l10n` with ARB files (`en`, `ar`) + `intl`. Full bidirectional (LTR + RTL).
- **Push** — `firebase_messaging` + `flutter_local_notifications`.
- **Forms/validation** — `flutter_form_builder` + `form_builder_validators` (or hand-rolled; keep it consistent).
- **Env/flavors** — `--dart-define-from-file` with per-flavor JSON; Android product flavors + iOS schemes.

> When you run `flutter pub add`, capture the resolved versions in `pubspec.yaml` and note them in `docs/decisions/stack.md`.

---

## 3. Backend integration — Magento GraphQL

### 3.1 Endpoint, store selection & headers
- **Endpoint:** `POST https://zoonze.com/graphql`
- **Store selection (critical):** Magento GraphQL picks the store view from the HTTP header **`Store: <store_view_code>`**. Because the app is bilingual, **this header is dynamic** — it must reflect the active store view and change at runtime when the user switches language:
  - locale `en` → `Store: uae-en`
  - locale `ar` → `Store: uae-ar`
  - (confirm exact codes; see §3.3)
- **Currency:** optionally `Content-Currency: AED` (only if multi-currency is enabled per store; otherwise the store's base currency applies).
- **Auth (logged-in):** `Authorization: Bearer <customer_token>`.
- **No CSRF/cookies** are needed for native GraphQL token auth. Do not port web session logic.

Implement as a **`graphql_flutter` Link chain**: `AuthLink` (injects bearer when present) → **`StoreLink`** (injects the `Store` header from the active store code, read from the locale/store controller — **not** static) → `HttpLink` → error link (maps 401 → token refresh/logout; maps WAF/HTML responses → friendly error).

**Cache + store switching:** the normalized `GraphQLCache` holds locale- and currency-specific data (prices, labels, category names). On a store/language switch you **must reset (or namespace) the cache and refetch** active screens — otherwise the user sees stale-language/stale-price data. Treat a store switch as: persist new locale → reset cache → rebuild router/Directionality.

### 3.2 Authentication flow
- **Login:** `generateCustomerToken(email, password)` → store token in secure storage. Magento tokens are long-lived but can be invalidated; treat a `graphql-authorization` / 401 as "log out and re-auth".
- **Register:** `createCustomerV2(input)` then immediately `generateCustomerToken`.
- **Logout:** `revokeCustomerToken` then wipe secure storage + reset Riverpod auth state + clear the customer cart id.
- **Password reset:** `requestPasswordResetEmail` → `resetPassword`.
- **Guest support:** the app must work logged-out for browse + guest cart. Decide guest-checkout policy under Open Questions.

> A customer token is **not** store-scoped, but cart and some address/locale behaviour are. Keep the active store consistent across an authenticated session; re-evaluate cart after a store switch.

### 3.3 Enumerate store views first (do this in Phase 0)
Run **`availableStores`** to get the authoritative list of store views with their exact codes, locales, currency, default flag, and base URLs — do **not** hardcode from the URL path:

```graphql
{
  availableStores(useCurrentGroup: false) {
    store_code
    store_name
    locale
    is_default_store
    base_currency_code
    default_display_currency_code
    base_url
    secure_base_url
    base_media_url
  }
}
```

Map the returned `store_code` values to app locales (`en` → English code, `ar` → Arabic code), record the **default** store view and the **currency**, and write the result into `AppConfig`/`docs/decisions/stores.md`. Everything else (Store header, currency formatting, default locale) flows from this.

### 3.4 Core operations to wire (typed via codegen)
Organize `.graphql` files by feature under `lib/<feature>/data/graphql/`.

**Catalog & browse**
- `categoryList` / `categories` — menu tree, category landing.
- `products(filter, search, sort, pageSize, currentPage)` — PLP, search results, pagination.
- Single product by `url_key` / `sku` — PDP.
- For **configurable products**: pull `configurable_options { attribute_code, label, values { value_index, label, swatch_data { value } } }` and `variants { attributes { code value_index } product { sku, price_range, media_gallery, stock_status } }`. Drive swatch UI and price/stock updates from variant selection.
- **Filters/aggregations**: read `aggregations` from the `products` query to build the PLP filter panel dynamically (don't hardcode attributes).
- **Search**: start with native `products(search:)`. If **Adobe/Live Search** is enabled, switch to the `productSearch`/Live Search schema (confirm under Open Questions).

**Cart (guest + customer)**
- `createEmptyCart` → cart id. Persist guest cart id (hive); on login, **merge** guest cart into customer cart with `mergeCarts(source_cart_id, destination_cart_id)`.
- `addProductsToCart(cartId, cartItems)` — use the unified mutation (handles simple + configurable via `selected_options`/`parent_sku`). Avoid the deprecated per-type mutations.
- `cart(cart_id)` — full cart query (items, prices, applied coupons, totals).
- `updateCartItems`, `removeItemFromCart`, `applyCouponToCart`, `removeCouponFromCart`.

**Checkout**
- `setShippingAddressesOnCart` (or use saved customer address).
- `setBillingAddressOnCart`.
- Read `cart { shipping_addresses { available_shipping_methods } }` → `setShippingMethodsOnCart`.
- `cart { available_payment_methods }` → `setPaymentMethodOnCart`. This list is the source of truth for which methods to show; **Tabby may appear conditionally** (eligibility / cart-value thresholds) — never hardcode it as always-available.
- `placeOrder(cart_id)` → order number. **N-Genius adds a redirect step here — see §5.**

**Customer account**
- `customer` — profile, addresses.
- `customerOrders` / `customer { orders }` — order history + detail.
- `createCustomerAddress`, `updateCustomerAddress`, `deleteCustomerAddress`.
- `updateCustomerV2`, `changeCustomerPassword`.

**Wishlist**
- `customer { wishlists { items_v2 } }`, `addProductsToWishlist`, `removeProductsFromWishlist`.

**Reviews**
- `product { reviews }`, `productReviewRatingsMetadata`, `createProductReview`.
- Prior store audit found **zero reviews**. The PDP must degrade gracefully (no fake stars) when review data is absent.

### 3.5 Media / image URLs
Resolve product image base URL from the GraphQL `media_gallery`/`image` fields (and `base_media_url` from `availableStores`). If relative, prefix with the store's media base. Confirm media is served through CloudFront and cacheable.

---

## 4. Architecture & project structure

**Feature-first, layered.** Each feature owns `data / domain / presentation`. Shared cross-cutting code lives in `core/`.

```
lib/
  main_dev.dart            # entrypoint per flavor
  main_staging.dart
  main_prod.dart
  app/
    app.dart               # MaterialApp.router, theme, localization + Directionality wiring
    router.dart            # go_router config + guards (auth, deep links)
    theme/                 # colors, typography (Arabic + Latin fonts), directional-aware
  core/
    graphql/               # link chain (auth, store, http, error), client provider, cache
    config/                # AppConfig from --dart-define (endpoint, store codes, currency)
    store/                 # active store view + locale controller (drives Store header)
    error/                 # Failure types, exception→Failure mapping
    network/               # dio instance, connectivity
    storage/               # secure storage + hive boxes
    localization/          # l10n helpers, locale controller, RTL/LTR utils
    widgets/               # shared UI (buttons, price, loaders, empty/error states)
  features/
    catalog/               # home, categories, PLP, PDP
    search/
    cart/
    checkout/              # address, shipping, payment, place order, N-Genius webview
    auth/                  # login, register, reset
    account/               # profile, addresses, orders, language switch
    wishlist/
    reviews/
    notifications/         # FCM handling, topic subscription
  l10n/                    # app_en.arb, app_ar.arb
test/                      # unit + widget tests mirroring lib/
integration_test/          # critical-path flows (browse→cart→checkout)
```

**Within a feature:**
- `data/` — GraphQL operation files, DTOs (codegen output), repository implementation.
- `domain/` — entities, repository interface, use-case-style methods (keep light; don't over-abstract).
- `presentation/` — Riverpod providers/notifiers + screens + widgets.

**Rules:** presentation never touches GraphQL directly; it goes through a repository. Repositories return domain entities or `Failure`, never raw GraphQL maps. No business logic in widgets.

---

## 5. Payments — redirect gateways: N-Genius + Tabby (handle with care)

Both methods are **redirect-based**, not inline forms, and both depend on how their **Magento extension exposes the checkout session through GraphQL** — **the highest-risk integration; likely needs backend confirmation/work.** Build **one shared redirect engine** and parameterize it per provider.

- **N-Genius** (Network International) — card payment via **hosted payment page (HPP)**.
- **Tabby** — **BNPL** ("Pay in 4" interest-free installments), the dominant split-pay option in the UAE/GCC. Redirects to Tabby's hosted checkout.

**Shared flow (both gateways):**
1. `setPaymentMethodOnCart` with the provider's method code.
2. `placeOrder` → order in pending-payment state; the response (or a companion query/REST call the extension exposes) yields a **redirect URL**.
3. Open that URL in `flutter_inappwebview`.
4. Intercept navigation; detect the **return URL** (success / failure / cancel / **reject**). Use a deep-link-friendly return URL so WebView + push routing stay consistent.
5. On return, **re-query order status server-side** (never trust the client redirect alone) before showing success.

**Tabby-specific:**
- **Eligibility is conditional.** Tabby pre-scores the customer and enforces min/max order value and currency (AED). Drive its visibility **only** from `cart { available_payment_methods }` — if Magento/Tabby doesn't return it, don't show it.
- **Rejection mid-flow is a normal path,** not an error. Tabby can decline an eligible-looking customer during checkout; handle the reject return cleanly and bounce the user back to method selection with the other options intact — don't crash or show a generic failure.
- **"Pay in 4" promo messaging** on PDP and cart (e.g. "4 interest-free payments of AED X") is a standard Tabby requirement with brand guidelines. Compute the breakdown from the localized price and gate it on Tabby availability. Confirm scope in Open Questions.
- **Sandbox testing:** Tabby provides test identities/scenarios to simulate success, reject, and expiry — use them in the checkout integration tests rather than mocking blindly.

**N-Genius-specific:**
- Standard HPP card flow; confirm whether a native N-Genius mobile SDK is preferred over HPP.

> **Verify before building (each gateway separately):** Does the installed extension expose the redirect/session URL via **GraphQL**, REST only, or a **native mobile SDK**? If GraphQL coverage is missing, a small custom Magento resolver may be needed. Flag to the owner early — do not stub a fake card form or fake installment UI.

Never store or transmit raw PAN/CVV or BNPL identity data through the app. All capture happens on the provider's page/SDK.

---

## 6. Localization, currency & bidirectional layout (first-class, not an afterthought)

The store ships **two views**; the app is **bilingual** with a runtime language switcher.

- **English (`en`)** → store `uae-en` → **LTR**. **Arabic (`ar`)** → store `uae-ar` → **RTL**. Both must be fully designed and QA'd — neither is a second-class citizen.
- Confirm which store view is the **default** (sets first-launch language before the user chooses).
- **Language switch is a store switch:** changing language must (1) update locale + `Directionality`, (2) flip the GraphQL `Store` header, (3) reset/refetch the GraphQL cache (prices/text differ), (4) rebuild the router. Persist the choice (shared_preferences).
- **Directional layout:** never hardcode `EdgeInsets.only(left:)` / `Alignment.centerLeft` — use `*Directional` insets/alignment everywhere so LTR↔RTL flips correctly. Test every screen in both directions.
- **Currency:** format **AED** with `intl` `NumberFormat`. Prefer prices from GraphQL `price_range`/`prices` (already store-localized) over client-side conversion.
- **Numerals:** decide Eastern Arabic (٠١٢) vs Western (012) for the Arabic view — confirm with owner.
- **Fonts:** quality Arabic typeface (e.g. Cairo / Tajawal) + Latin fallback; bundle and set in theme.
- **Strings:** app-chrome strings live in ARB (`en`/`ar`); product/category text comes from GraphQL via the `Store` header. No string literals in widgets.

---

## 7. Networking / infra notes (CloudFront + WAF)

The origin sits behind CloudFront + AWS WAF. The app's GraphQL traffic must not be mistaken for bot traffic or stripped by edge rules.

- Confirm a CloudFront behavior for `/graphql` that **allows POST** (and OPTIONS), with caching **disabled** for GraphQL and an origin-request policy that **forwards `Store`, `Authorization`, `Content-Type`, and `Content-Currency` headers**.
- Confirm AWS WAF managed rules don't block the app's POST bodies or User-Agent. Set a clear, stable User-Agent (e.g. `ZoonzeApp/<version> (Flutter)`) so it can be allow-listed.
- Prior store work hit WAF/bot-blocking on dynamic endpoints — expect to coordinate a WAF rule for app traffic.
- Retry-with-backoff on transient 5xx/timeout; global "service unavailable" UI when the edge returns HTML instead of JSON (detect non-JSON in the error link).

---

## 8. Environment config & flavors

Three flavors: **dev / staging / prod**. Use `--dart-define-from-file`.

`config/dev.json`
```json
{
  "FLAVOR": "dev",
  "GRAPHQL_ENDPOINT": "https://zoonze.com/graphql",
  "DEFAULT_LOCALE": "en",
  "STORE_CODE_EN": "uae-en",
  "STORE_CODE_AR": "uae-ar",
  "CURRENCY": "AED",
  "USER_AGENT": "ZoonzeApp-dev"
}
```

- Store codes here are **provisional** — overwrite with the exact `store_code` values returned by `availableStores` (§3.3); they may be `uae_en`/`uae_ar`.
- `AppConfig` reads these via `String.fromEnvironment`. The store/locale controller maps the active locale to the right `Store` code at request time.
- **No secrets in the repo** — Firebase config files and signing keys stay out of git (mirror the project's `auth.json` hygiene rule).
- Android `applicationId` / iOS bundle id: propose **`com.zoonze.shop`** (confirm). Distinct ids per flavor (`...shop.dev`).
- Run: `flutter run --dart-define-from-file=config/dev.json --flavor dev`.

---

## 9. Conventions & rules for Claude Code

- **Introspect, don't assume.** Verify every field against the live 2.4.8-p5 schema; confirm store codes via `availableStores` before wiring the Store header.
- **Typed everything.** Use `graphql_codegen`; no untyped map access in feature code.
- **Repository boundary is sacred.** UI ↔ providers ↔ repository ↔ GraphQL. Never short-circuit.
- **Errors are values.** Map exceptions to `Failure` at the data layer; surface localized messages; never show raw GraphQL errors to users.
- **Images go through `ZoonzeImage`** (`lib/core/widgets/network_image.dart`) — never a bare `CachedNetworkImage`. It owns the no-fade policy, decode sizing and the cache manager; a call site that bypasses it silently reinstates a ~1s dissolve. Pre-warm only via `ZoonzeImage.provider` at the same decode width the widget uses.
- **Bidirectional by default.** Every screen reviewed in both `en` (LTR) and `ar` (RTL). Use directional layout primitives.
- **Store switch is atomic.** Locale + Store header + cache reset + router rebuild happen together.
- **No fabricated data.** If reviews/swatches/stock are absent in the API, render the empty/neutral state — don't invent stars or shade counts.
- **Security.** Token in secure storage only; no PAN handling; TLS pinning optional but recommended for prod.
- **Tests for critical paths.** Unit-test repositories (mock the GraphQL client); widget-test PDP/cart in both directions; integration-test browse→add-to-cart→checkout (mock payment).
- **Small, reviewable commits**, each tied to a roadmap step. Keep `docs/decisions/*.md` updated when a stack/architecture/store choice is made.
- **Lint:** enable `flutter_lints` (or `very_good_analysis`) and keep the analyzer clean.

---

## 10. Phased roadmap

Build in vertical slices; each phase ends shippable to internal testers.

**Phase 0 — Foundation**
Scaffold project + flavors + `AppConfig`; run `availableStores` and record exact codes/currency/default; wire the `graphql_flutter` link chain (dynamic Store header, auth link, error mapping, cache-reset-on-switch); set up Riverpod, go_router, theming, ARB, **bidirectional layout + language switcher**, secure storage, hive. Health-check the live endpoint (`storeConfig`) for **both** store views.

**Phase 1 — Catalog browse (logged-out)**
Home (categories + featured), category PLP with aggregations-driven filters + sort + pagination, PDP with gallery + configurable swatches + price/stock per variant, search. Verify content switches correctly between EN/AR. No cart yet.

**Phase 2 — Cart + Auth**
Guest cart (`createEmptyCart`, `addProductsToCart`), cart screen (update/remove, coupons, totals), login/register/reset, **cart merge on login**, customer state across app.

**Phase 3 — Checkout + payments (N-Genius + Tabby)** _(app side delivered; native modules + backend `MagentoEgypt_PaymentGraphQl` are the on-platform steps)_
Address (saved + new), shipping methods, payment selection driven **only** by `available_payment_methods`, `placeOrder`, one shared native-SDK payment seam (`zoonze/payments` channel + `runPaymentSession`) + return/**reject** handling via `CompletePaymentScreen` + server-side order confirmation, Tabby eligibility gating + "Pay in 4" promo on PDP/cart. **Non-gateway methods** — Magento **Zero Subtotal Checkout** (`free`, total = 0) + cash on delivery — are detected as `!isRedirect` and finalise on `placeOrder` with no payment step. **Apple Pay + Samsung Pay** (CL042-DEV24/DEV27) ride the *same* N-Genius session as a new `wallet` argument on the `pay` call — no new `PaymentGateway` value — and are filtered by a `walletAvailability` device probe, because the API offers them regardless of hardware. Checkout order is Apple Pay → Samsung Pay → Visa & MasterCard → Tabby → Cash on Delivery (verified on device 2026-08-20: with no wallet methods served yet the live list renders Visa & MasterCard → Tabby → Cash On Delivery, COD pre-selected). (Payment Open Questions §2/§3 resolved.) **Saved cards** (CL042-DEV25) use **core Magento Vault**, not a bespoke store: `customerPaymentTokens` / `deletePaymentToken` (already live) for list/delete, `ngeniusonline: { is_active_payment_token_enabler }` to save, and an `ngeniusonline_vault` method code + `VaultTokenInput { public_hash }` to pay — folded *into* the card row, never a second row. Which SDK screen opens is decided from the order's `savedCard`, so the `pay` channel gains no argument and no CVV/PAN ever reaches Dart. Contract `docs/backend/payment-contract.md` §④; rationale `docs/decisions/saved-cards.md`.

**Phase 4 — Account + Wishlist + Reviews**
Profile, address book, order history + detail, wishlist, write/read reviews (graceful empty states), language switch in settings.

**Phase 5 — Push + polish**
FCM (order/promo topics), deep links, performance pass, EN/AR + RTL/LTR QA sweep, store-listing assets, release flavors + signing.

---

## 11. Open Questions (resolve with owner before Phases 3–5)

1. **Store codes & default:** Confirm exact `store_code` values (`uae-en`/`uae-ar` vs `uae_en`/`uae_ar`) from `availableStores`, and **which view is the storefront default** (first-launch language).
2. **Payment integration (per gateway):** _(Resolved: **native SDK** for Phase 3.)_ The app integrates **N-Genius** (`ngeniusonline` — native `payment-sdk-android` / iOS `NISdk`) and **Tabby** (`tabby/m2-checkout`) behind a provider-agnostic `PaymentGateway` seam; **both gateways are driven through one native `MethodChannel` (`zoonze/payments` → `pay`)** — there is no Flutter WebView redirect engine. **Backend dependency:** a new Magento module **`MagentoEgypt_PaymentGraphQl`** exposes two queries — `paymentSession(order_number, email, lastname, token)` (gateway session for a placed order; `isReady == status==READY`; guest orders authorize via the order `token` or billing email+lastname, customers via the bearer — **live schema confirmed; the guest arg is named `token`, not `guest_token`**) and `tabbyConfig` (eligibility/promo). The Dart side already consumes both and degrades to "awaiting payment" / hidden promo until deployed. **Authoritative contract:** `docs/backend/payment-contract.md` (SDL + per-gateway resolver behaviour + native channel arg map + status-string mapping); app-side rationale + SDK versions + sandbox identities: `docs/decisions/payments.md`. _Tabby (resolved):_ **three** products — `INSTALLMENTS` ("Pay in 4"), `PAY_LATER`, `CREDIT_CARD_INSTALLMENTS` — each product's enable flag + min/max thresholds + `promo_enabled` are **backend config only** (`tabbyConfig`, one entry per product); the app hardcodes nothing. The **PDP/cart promo** (`TabbyPromo`) renders one line per promo-eligible product and the checkout method label reflects the product; all hidden when absent/out of range. The checkout method list still comes only from `available_payment_methods`. _Wallets (resolved 2026-08-20):_ **Apple Pay** (iOS, `NISdk`) and **Samsung Pay** (Android, `payment-sdk-samsungpay`) are **N-Genius wallet presentations, not gateways** — same order, same `order_response`, `gateway: NGENIUS`; only `method_code` differs (`ngeniusonline_applepay` / `ngeniusonline_samsungpay`), and the app maps it to a `wallet` arg (`card|applepay|samsungpay`) on the existing channel. They must arrive from `available_payment_methods` like any other method; the app adds nothing and only *filters* by a new `walletAvailability` channel probe (device capability is something the backend cannot see). Google Pay is deliberately **out of scope** on Android. External blockers — the Apple Pay processing certificate (CSR from N-Genius), regenerating both committed provisioning profiles, and Samsung Pay portal registration — are listed in `docs/decisions/payments.md` §5. **Post-order payment failure** (decline/cancel/expire/fail on a placed order, whose cart is consumed) routes to **`CompletePaymentScreen`** — both _pay later_ (order stays awaiting payment) and _pay now_ (retry same method via `paymentSession`, or switch via the `setOrderPaymentMethod` mutation). Shared `runPaymentSession` normalises status+outcome for checkout and retry. _Saved cards (resolved 2026-08-28, CL042-DEV25):_ **Magento Vault**, chosen over custom resolvers because the read/delete half (`customerPaymentTokens` / `deletePaymentToken` / `VaultTokenInput`) is already live and a card saved in the app then also appears on the website. Backend owes: vault rows for `ngeniusonline`, the `is_active_payment_token_enabler` save flag, the `ngeniusonline_vault` method code (advertised only when a token exists), and `SetOrderPaymentMethodInput.public_hash` for the retry screen. The app degrades to invisible without any of it — and the save opt-in *retries bare* rather than costing the shopper their order. Hard prerequisite: `docs/backend/ngenius-graphql-session.md` must be deployed, since saved cards ride the same session. Contract §④; rationale `docs/decisions/saved-cards.md`.
3. **Guest checkout:** _(Resolved: **allowed**.)_ Guests reach N-Genius/Tabby via `paymentSession(order_number, email, lastname, token)` — a guest authorizes by **either** the Magento order `token` (`placeOrder.orderV2.token`) **or** the **billing email + lastname** entered at checkout (resolver uses whichever validates); logged-in users send only `order_number` (bearer authorizes). Captured in `CheckoutState`/`PlaceOrderResult` and sent by `loadPaymentSession` for guest orders only. _(Live schema confirmed the 4-arg signature — the guest arg is named `token`, not `guest_token`.)_ **Guest order tracking (resolved 2026-08-21, CL042-DEV18):** guests never query `customer { orders }` (a hard 403 without a bearer, which rendered an unrecoverable error page). `CheckoutController.placeOrder()` persists a `GuestOrderRef` (order number + `orderV2.token` + billing email/lastname, hive key `guest_orders`), and `/orders` resolves it live through the **native** `guestOrderByToken` / `guestOrder` queries — same `CustomerOrder` type, so the existing parser and Track/Detail screens are reused. `/track-order` looks up any order by number + email + lastname. See `docs/decisions/guest-order-tracking.md`.
4. **Search:** Is **Adobe/Live Search** installed (use `productSearch` schema), or stock catalog search (`products(search:)`)?
5. **Catalog readiness:** Are products properly categorized (not "Default Category"), and are configurable swatches set up as real configurable attributes? The PLP/PDP can only show what's modeled in the catalog. _(Categorization **resolved** 2026-06-27 via live introspection: real categories with counts — Fragrance 737, Skincare 247, New Arrivals 120, Makeup 10, etc. — and `products(search:)` returns real SKUs with AED `price_range` + `stock_status`. **Still to verify:** configurable-swatch modeling, via a PDP `configurable_options`/`variants` query.)_
6. **Currency:** Confirm **AED** is the base/display currency for both views; any multi-currency handling needed?
7. **Numerals & formatting:** Eastern Arabic vs Western digits for the Arabic view; AED symbol/placement. _(Resolved: Western numerals, per Figma.)_
8. **Design source:** Is there a Figma for the app, or follow the approved redesign direction + a standard commerce pattern? _(Resolved: `docs/FIGMA_DESIGN.md` + Figma file.)_
9. **Firebase project:** Existing FCM project, or create one? Who owns signing keys / store accounts (Play Console, App Store Connect)?
10. **App identifiers:** Confirm `com.zoonze.shop` (and per-flavor suffixes).
11. **WAF/CDN:** Who can add the CloudFront `/graphql` POST behavior and the WAF allow-rule for the app User-Agent?

---

### First action for Claude Code
Start Phase 0. Before scaffolding, run **`availableStores`** and a per-view **`storeConfig`** against `https://zoonze.com/graphql` (header `Store: uae-en`, then `Store: uae-ar`). Report back both exact store codes, their locales, the currency, the default view, and base/media URLs — so the entire build is grounded in the real schema and real store config, not assumptions.

> **Phase 0 status:** Foundation delivered. The live `availableStores`/`storeConfig` introspection could not run from the build environment (egress policy blocks `zoonze.com`), so store config is **resolved dynamically at runtime** and confirmed on-network via `tool/introspect.sh`. See `docs/PLAN.md` and `docs/decisions/`.
