# Zoonze App — Full Build Plan (Phases 0–5)

## Context

`magentoegypt/zoonze-app` is a Flutter app: a headless storefront client for **Magento Open Source 2.4.8-p5** at `zoonze.com`, bilingual (EN/LTR + AR/RTL), **AED**, UAE market — brand **ZoonZE Beauty** (fragrance/beauty). CLAUDE.md is the binding spec; the app is a pure GraphQL client (no Magento PHP). `docs/FIGMA_DESIGN.md` (+ the Figma file) is the UI source of truth.

This is the **master plan across all phases with ETAs.** Execution is incremental ("vertical slices; each phase ends shippable; small reviewable commits"). **Phase 0 code is delivered to `main`.**

### Environment constraints (shape the plan)
- **`zoonze.com` is blocked** by the org egress policy (proxy 403 on CONNECT). Live `availableStores`/`storeConfig` can't run from CI — that runs from a network that reaches the origin (scripted in `tool/introspect.sh`).
- Flutter stable installed in-session; gated on `flutter analyze` + `flutter test`. Full Android device build (Android SDK) and iOS schemes (Xcode/macOS) are the developer's local step.

### Decisions confirmed with owner
1. **Build approach:** install the SDK and verify (analyze + tests green).
2. **Store config:** **dynamic resolution** — bootstrap with a default store code, query `availableStores` at runtime, derive `locale → store_code`, default view, and currency from the response. No hardcoded codes as source of truth.
3. **Scope:** full Phase 0 foundation; **all phases documented with ETAs.**
4. **Design (from `docs/FIGMA_DESIGN.md`):** Figma tokens in theme; **Inter** + **Playfair Display** (Latin), **Cairo** (Arabic). Full Arabic/RTL mirror of all **26 screens (52 frames)**; Western numerals; Latin brand/price/codes. **Onboarding removed** (Launch → Welcome → Sign In). Global chrome: persistent **bottom nav** + **marketing footer** on content screens; 1st-group screens chrome-free.

---

## Plan ETA (agent execution hours)

**Hands-on-keyboard wall-clock hours** per phase. Phase 0 includes one-time SDK install. Waiting on blockers (origin access, owner answers, backend/Xcode) is separate.

| Phase | Deliverable | Time (hours) | Solo? |
|---|---|---|---|
| **0** | Foundation (✅ done) | **~3–4 h** | ✅ except live introspection (origin blocked) → scripted |
| **1** | Catalog + splash + Menu Drawer + bottom nav + footer (EN+AR) | **~10–14 h** | ⚠️ Needs `schema.graphql` + catalog modeling (Open Q §4–§5) |
| **2** | Cart + Auth + live bottom-nav badges (EN+AR) | **~5–8 h** | ⚠️ Needs schema; guest-checkout policy (Open Q §3) |
| **3** | Checkout + N-Genius + Tabby (EN+AR) | **~8–13 h** | ❌ Gateway exposure (Open Q §2) + possible Magento work |
| **4** | Account + Wishlist + Reviews (EN+AR) | **~5–8 h** | ⚠️ Needs schema |
| **5** | Push + polish + 52-frame QA + release | **~5–7 h** (code) | ❌ Firebase / signing / WAF / macOS-Xcode |
| | **Total app code** | **≈ 36–54 h** | Gated by endpoint access + Open Questions §11 |

---

## PHASE 0 — Foundation (✅ delivered)

Feature-first layered architecture (CLAUDE.md §4); repository boundary sacred. Plain Riverpod + hand-written GraphQL documents for the two bootstrap ops (`availableStores`, `storeConfig`) — codegen (`riverpod_generator` + `graphql_codegen`) is introduced in Phase 1 once `schema.graphql` exists (see `docs/decisions/stack.md`).

**Delivered:**
- Flavors (`config/{dev,staging,prod}.json`) + `AppConfig` via `--dart-define-from-file`.
- GraphQL link chain: `AuthLink` → `StoreHeaderLink` (dynamic `Store` header + User-Agent) → `HttpLink`; exception→`Failure` mapping at the repository layer.
- **Dynamic store resolution** (`StoreController`): bootstrap code → `availableStores` → `locale→store_code` map + default + currency; Hive-cached; **atomic switch** (persist locale → invalidate client/cache → rebuild Directionality/theme).
- Theme from Figma tokens; locale-aware fonts (Inter/Cairo, Playfair for wordmark).
- Bilingual ARB (en/ar, Western numerals) + RTL/LTR + language toggle.
- Secure token storage, Hive cache, shared_preferences locale.
- `features/diagnostics` health-check screen (live `storeConfig` + language toggle).
- Entrypoints `main_{dev,staging,prod}.dart`; Android flavors (iOS schemes = local Xcode step).
- Tests: `StoreController` mapping/switch, failure mapper, `AppConfig`, health-check widget in **EN/LTR + AR/RTL**. `flutter analyze` clean, all tests green.

### Image assets (committed via PR #2)
`assets/branding/logo.png`, `favicon.ico`; `assets/images/banner.jpg`, `test_product{,_2,_3,_4}.jpg` (round-robin). `Image.asset(..., errorBuilder:)` degrades to a neutral placeholder (no fabricated imagery).

---

## PHASE 1 — Catalog browse (logged-out) + splash + global chrome · ETA ~10–14 h
**Deliver (EN+AR):** Splash (Launch + Welcome); home with decluttered app bar + **Menu Drawer** + persistent **bottom nav** (cart/wishlist badge shells) + **marketing footer**; PLP (aggregations filters + sort + pagination), PDP (gallery, configurable swatches, per-variant price/stock; share below wishlist), search. Build to `docs/FIGMA_DESIGN.md` EN + AR/RTL frames. PDP reviews degrade to empty state (store has zero — no fabricated stars).
**Ops:** `categoryList`/`categories`, `products(...)`, product by `url_key`/`sku`, `configurable_options`+`variants`, `aggregations`. **Introspect `schema.graphql` → graphql_codegen.**

## PHASE 2 — Cart + Auth · ETA ~5–8 h
Guest cart + cart screen (update/remove, coupons, totals); Sign In/Up (name+email+password, no OTP)/Forgot; **cart merge on login**; live cart badge. Ops: `createEmptyCart`, `addProductsToCart`, `cart`, `updateCartItems`, `removeItemFromCart`, coupons, `mergeCarts`, `generateCustomerToken`, `createCustomerV2`, `revokeCustomerToken`, reset.

## PHASE 3 — Checkout + N-Genius + Tabby · ETA ~8–13 h · **HIGH RISK**
Checkout per Figma (numbered steps; payment options as selectable cards; Tabby brand chip); payment list from `available_payment_methods`; `placeOrder`; **one shared redirect-WebView engine**; return/**reject** + **server-side order re-query**; Tabby eligibility + "Pay in 4". **Resolve Open Q §2 first** (GraphQL/REST/SDK exposure; possible Magento resolver). No fake card/installment UI.

## PHASE 4 — Account + Wishlist + Reviews · ETA ~5–8 h
My Account, Edit Profile, Addresses CRUD, Orders + Tracking, Wishlist (+ badge), Notifications, Help, reviews (graceful empty states), language switch in settings.

## PHASE 5 — Push + polish + release · ETA ~5–7 h
FCM + local notifications, deep links, perf pass, **52-frame EN/AR QA sweep**, store assets, release flavors + signing. Depends on Firebase/signing/WAF owner tasks.

---

## Cross-cutting rules
Introspect don't assume · typed everything (Phase 1 codegen) · repository boundary sacred · errors are values → localized `Failure` · bidirectional by default (EN/LTR + AR/RTL; Cairo for AR, Western numerals, Latin brand/price/codes) · store switch atomic · no fabricated data · token in secure storage / no PAN handling · build to Figma tokens · analyzer clean.

## Verification
- **Phase 0 gate (in-session):** `flutter pub get`, `flutter gen-l10n`, `flutter analyze` clean, `flutter test` green.
- **On-network (origin blocked in CI):** `bash tool/introspect.sh` → confirm store codes/default/currency, update `docs/decisions/stores.md` + config, emit `schema.graphql`; then `flutter run --dart-define-from-file=config/dev.json --flavor dev` → health-check shows live storeConfig; language toggle flips header + RTL + font + refetches.

## Flagged for owner
- **Font:** Arabic = **Cairo** (matches Figma); EN = Inter + Playfair.
- iOS schemes/signing need macOS/Xcode (Android flavors wired).
- Store codes/default/currency **unconfirmed** until `tool/introspect.sh` runs on-network (resolved dynamically, non-blocking).
- Figma PDP reviews are illustrative; live store has zero → empty state.
- **Open Questions §11** (payment exposure, guest checkout, Live Search, Tabby thresholds/promo, Firebase, WAF owner, app ids) gate Phases 3–5. (§7 numerals resolved: Western.)
