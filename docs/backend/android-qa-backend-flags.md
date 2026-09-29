# Android QA — Backend / Config Flags

Items surfaced by the Android QA passes ([ClickUp **Android** 86d3hjbc4](https://app.clickup.com/t/86d3hjbc4)) that **cannot be fixed in the Flutter app** — they need Magento admin config or a backend/GraphQL change. The app side for each is already built to consume the data the moment the backend provides it (or degrades gracefully until then).

Owner: **Magento / platform team**. Endpoint: `https://zoonze.com/graphql`, per store view (`Store: uae-en` / `Store: uae-ar`).

| # | Flag | Area | Blocking? | Effort |
|---|------|------|-----------|--------|
| 1 | Free-shipping carrier not offering a free method at threshold | Checkout | Ships wrong shipping cost | Config only |
| 2 | Footer social URLs (X + YouTube) missing from config | Home footer | Cosmetic | Config only |
| 3 | Shop-by-Category source doesn't match the website | Home | Cosmetic/UX | Config or small resolver |
| 4 | Arabic push-notification text | Notifications | UX | Send-side change |
| 5 | ~~Address "Save as" (Home/Office/Other) label~~ **✅ RESOLVED** (attr live + app wired) | Addresses | Done | Custom attribute |
| 6 | "Continue with Google" social login | Sign-in | Feature (deferred) | Extension + resolver |
| 7 | ~~Profile-photo (avatar) upload~~ **✅ RESOLVED** (backend live + app wired) | Edit Profile | Done | Custom resolver + storage |
| 8 | Product "size" not modelled as a configurable attribute | PDP | Cosmetic/UX | Catalog |
| 9 | ~~Customer token lifetime at Magento's 1-hour default~~ **✅ RESOLVED** (set to 720h) | Sign-in | Done | Config only |

---

## 1. Free-shipping carrier — cart shows FREE but checkout charges
**ClickUp:** [Checkout 86d3j9h2q](https://app.clickup.com/t/86d3j9h2q) #3 · **Priority: High** (customers are charged shipping they were promised is free).

**Symptom.** With subtotal above the threshold the cart shows **FREE** delivery, but at checkout only a paid method (flat rate) is returned, so shipping is charged. QA also references **AED 150** while the current config value is **AED 200**.

**App state (already correct).** The app reads the threshold from `storeConfig.free_shipping_subtotal` (never hardcoded), shows *FREE* vs *"Calculated at checkout"* reactively, and renders `cart.available_shipping_methods` verbatim. It does **not** and should not override server shipping totals.

**Root cause.** The threshold value (`free_shipping_subtotal`) is set, but Magento's **Free Shipping carrier is not actually offering a free method** at that subtotal — so the app's promise and the checkout quote diverge.

**Backend action.**
- `Stores → Configuration → Sales → Shipping Methods → Free Shipping`: set `carriers/freeshipping/active = Yes` for **both** `uae-en` and `uae-ar`, with `carriers/freeshipping/free_shipping_subtotal` = the intended amount. *(Or a Cart Price Rule granting free shipping when subtotal ≥ X — but keep the number equal to what `free_shipping_subtotal` reports, since the app reads that field for its banner.)*
- **Reconcile the threshold:** confirm the single correct value (150 vs 200) and set it consistently.

**Acceptance.** Query `cart { available_shipping_methods { carrier_code method_code amount { value } } }`:
- subtotal **≥** threshold → the list includes a method with `amount.value = 0`;
- subtotal **<** threshold → it does not.

---

## 2. Footer social links — X (Twitter) & YouTube missing
**ClickUp:** [Home 86d3hm7bf](https://app.clickup.com/t/86d3hm7bf) #4 · **Priority: Low.**

**Symptom.** The footer shows only Facebook + Instagram; the design calls for **Instagram · X · YouTube · Facebook**.

**App state (already built).** The footer renders all of Instagram / X / YouTube / Facebook (correct order + glyphs) — but it reads the URLs **straight from config** with no fallback merge once config loads, so a blank config field = no icon.

**Backend action.** In the `magentoegypt_beauty` admin section, populate these `magentoegypt_beauty_config` paths for **both** store views (currently only facebook/instagram are set):
- `footer/twitter_url` → the X profile URL
- `footer/youtube_url` → the YouTube channel URL
- (verify `footer/facebook_url`, `footer/instagram_url` are still set)

**Acceptance.** `storeConfig { magentoegypt_beauty_config { path value } }` returns non-empty `footer/twitter_url` and `footer/youtube_url`.

---

## 3. Shop-by-Category doesn't match the website
**ClickUp:** [Home 86d3hm7bf](https://app.clickup.com/t/86d3hm7bf) #3 · **Priority: Medium.**

**Symptom.** The home "Shop by Category" rail surfaces *New Arrivals / Bestsellers* rather than the website's curated set (Lipsticks, Eyes, Face…), in a different order, with different images.

**App state.** The rail is driven by the category tree returned from GraphQL; the app renders whatever categories/positions/images the backend provides.

**Backend action (decision needed).** Pick a source of truth so app and web match:
- **(a)** Configure the category **node membership, `position`, and category images** the app should read (a dedicated "Shop by Category" parent or the front-page display flag), **or**
- **(b)** Expose a **curated list** the way `heroSlides` / `brands` are already exposed by `MagentoEgypt_BeautyTheme`, returning `{ label, image, category_uid }` in display order.
- Provide the intended **categories, order, and images**.

**Acceptance.** A defined, ordered, image-backed category list the app can query that matches the website's Shop-by-Category section.

---

## 4. Arabic push-notification text
**ClickUp:** [My Orders 86d3jefcx](https://app.clickup.com/t/86d3jefcx) #5 (notification details) · **Priority: Medium.**

**Symptom.** In the Arabic app, notification `title`/`body` still show English.

**App state.** The inbox renders the FCM payload's `title`/`body` **verbatim** (chrome/timestamps are localized). The app can't translate arbitrary server-authored text client-side.

**Backend action.** Localize push payloads **at send time**: send `title`/`body` in the recipient's store-view/locale (preferred), **or** include both languages plus a `locale`/data key so the client can select. See [`docs/backend/notifications-contract.md`](notifications-contract.md).

**Acceptance.** A customer whose store view is `uae-ar` receives Arabic `title`/`body`.

---

## 5. Address "Save as" label (Home / Office / Other) — ✅ RESOLVED
**ClickUp:** [My Orders 86d3jefcx](https://app.clickup.com/t/86d3jefcx) #4 (Add Address) · **Status: Done** (attribute live; app wired 2026-07-09).

**Delivered:** `address_label` is a **select** attribute (options Home/Office/Other → option ids). App writes `custom_attributesV2: [{ attribute_code: "address_label", value: "<option-id>" }]`, reads it back via `custom_attributesV2 { ... on AttributeSelectedOptions { selected_options { label value } } }`, and discovers the option ids at runtime via `customAttributeMetadataV2` (no hardcoded ids/labels — labels are store-scoped). Chips on Add/Edit Address; a badge on Saved Addresses. Original request below.


**Symptom.** The design has "Save as: Home / Office / Other" chips; the app omits them.

**App state.** Omitted because there is **no field to persist the label** — Magento customer addresses have no nickname attribute wired to GraphQL.

**Backend action.** Add an **address custom attribute** (e.g. `address_label`) and expose it on `customerAddress` for **create / update / read** (`createCustomerAddress`, `updateCustomerAddress`, `customer { addresses }`).

**Acceptance.** The address mutations accept and the customer query returns `address_label`.

---

## 6. "Continue with Google" social login
**ClickUp:** [Sign in 86d3hkqb7](https://app.clickup.com/t/86d3hkqb7) · **Priority: Deferred** (product decision).

**Symptom.** Design shows "or continue with Google"; not implemented.

**App state.** No social-login dependency/UI (deferred by decision).

**Backend action (decision + build).** Magento has no native Google login. Needs a social-login extension exposing a **GraphQL mutation** (e.g. `socialLogin(provider: "google", token: <id_token>) → { customer_token }`) plus a Google OAuth client id. Then the app can add `google_sign_in` + wire the token exchange.

**Acceptance.** A GraphQL mutation that accepts a Google ID token and returns a valid customer token.

---

## 7. Profile-photo (avatar) upload — ✅ RESOLVED
**ClickUp:** [Edit Profile 86d3k12jt](https://app.clickup.com/t/86d3k12jt) · **Status: Done** (backend `MagentoEgypt_PaymentGraphQl` deployed; app wired 2026-07-09).

**Delivered API** (customer token): `uploadCustomerAvatar(input: { base64_encoded_file }) { url }`, `deleteCustomerAvatar { url }`, `customer { avatar_url }`. The app now picks from the gallery → base64 → uploads, shows the photo (falling back to initials), and offers Change / Remove. Below is the original request for reference.


**Symptom.** "Change Photo" shows "not available yet"; upload does nothing.

**App state.** Button is an intentional stub; the avatar renders customer initials. No mutation exists to call.

**Backend action (decision + build).** Magento has no customer-avatar concept. Needs a **custom resolver** to upload/store an image (e.g. `uploadCustomerAvatar(file) → { url }`, or a customer custom attribute holding a media URL) + media storage, and a field to read it back on `customer`.

**Acceptance.** A GraphQL mutation to set a customer avatar and a `customer` field to read its URL.

---

## 8. Product "size" selector (PDP) — catalog modelling
**ClickUp:** [Product Display 86d3htxb9](https://app.clickup.com/t/86d3htxb9) #1 · **Priority: Low** (also CLAUDE.md Open Q #5).

**Symptom.** The PDP shows an empty space above the quantity where a size selector should be.

**App state.** The size/variant selector already renders above the quantity **for configurable products** (`configurable_options` → chips, with per-variant price/stock). Simple products expose no size attribute, so there is nothing to select — the app does not fabricate one.

**Backend action.** Model size as a real **configurable attribute** (with variants) on the products that have sizes, so `products { ... configurable_options { attribute_code values { label } } variants { attributes { code value_index } product { sku price_range stock_status } } }` returns them.

**Acceptance.** A sized product returns non-empty `configurable_options` (attribute_code `size`) + `variants`; the PDP then shows the size chips above quantity automatically.

---

## 9. Customer token lifetime — customers signed out after an hour — ✅ RESOLVED
**ClickUp:** [CL042-DEV20 86d433b6p](https://app.clickup.com/t/86d433b6p) · **Status: Config applied 2026-08-26**
(`Customer Token Lifetime (hours) = 720`, *Use system value* unchecked). Awaiting the overnight on-device
confirmation. Original request below.

**Symptom.** *"The login time is way too short, we need the customer to stay logged in for a longer period."*

**App state.** Correct. `generateCustomerToken` is stored in secure storage and sent on every request; the app only
drops to guest when Magento actually rejects the bearer. Magento GraphQL exposes no refresh token, so the app has
no way to extend a session — the TTL is entirely a server-side setting.

**Root cause.** `oauth/access_token_lifetime/customer` is at Magento's **1-hour** default.

**Backend action.** `bin/magento config:set oauth/access_token_lifetime/customer 720` (30 days) + `cache:flush`.
Full detail, the non-bug sign-out causes, and an optional sliding-session mutation:
[`docs/backend/session-lifetime.md`](session-lifetime.md).

**Acceptance.** A customer signed in on the app is still signed in the next day.

---

### Not a backend flag (app-side, already handled)
For reference — these looked backend-ish but were resolved in-app during the QA passes, no backend action needed:
- **Checkout / My Orders stale on language switch** — fixed app-side (store-switch listeners on the checkout & orders controllers).
- **Customers randomly signed out at app launch** — separate from flag #9's hourly expiry. `StoreController._load()`
  wiped the customer token whenever the bootstrap `availableStores` call returned a non-JSON body, which is usually a
  transient WAF/CloudFront page rather than a bad token. Fixed app-side: the token is only cleared once a token-less
  retry proves the bearer was at fault.
- **Stale free-shipping offer at checkout after removing an item** — already handled by the checkout state `reset()` on entry (the quote is re-evaluated). The *only* remaining free-shipping item is flag **#1** above.
