# Zoonze App

Production-grade **Flutter** app — a bilingual (English/LTR + Arabic/RTL) headless
storefront client for the **ZoonZE Beauty** Magento Open Source 2.4.8-p5 backend
(`zoonze.com`, UAE, AED). Pure GraphQL client; no Magento PHP.

**Status (EN + AR/RTL throughout; `flutter analyze` clean, tests green):**
- **Phase 0 — Foundation** ✅ flavors, `AppConfig`, GraphQL link chain (dynamic
  `Store` header, retry-with-backoff + mid-session logout), dynamic store
  resolution, theme (Figma tokens + Inter/Cairo/Playfair), ARB + language
  switcher, secure storage + Hive, diagnostics.
- **Phase 1 — Catalog browse** ✅ app shell (drawer, bottom nav, footer),
  splash/welcome, home, PLP (aggregation filters incl. price range, sort,
  pagination), PDP, search.
- **Phase 2 — Cart + Auth** ✅ guest cart, coupons, merge-on-login; sign
  in/up/forgot + in-app reset, account.
- **Phase 3 — Checkout + payments** ✅ _app side._ Address → shipping → payment
  (driven only by `available_payment_methods`) → `placeOrder` → one native-SDK
  payment seam (`zoonze/payments` channel); N-Genius + Tabby via
  `paymentSession`/`tabbyConfig`, Tabby promo (PDP/cart), Zero Subtotal
  Checkout (`free`), and post-order recovery (`CompletePaymentScreen`). The
  GraphQL payment contract is **verified field-for-field against the live
  schema** (see `docs/backend/payment-contract.md`). **Remaining:** the native
  N-Genius/Tabby SDK modules behind the channel (a device/native step) — the
  Dart side degrades to "awaiting payment" until they land.
- **Phase 4 — Account/Wishlist/Reviews** ✅ wishlist (+ live badge), orders +
  detail/tracking, addresses, edit profile, reviews, Help & FAQ, Settings.
- **Phase 5 — Push + release** ✅ _app side._ FCM + local notifications, deep
  links, notification settings, performance pass, CI + Android/iOS release
  workflows. **Remaining (owner/platform):** Firebase per-flavor registration,
  signing secrets, iOS Team ID / `match`, and store submission.

See `CLAUDE.md` (binding spec), `docs/PLAN.md` (phased roadmap + ETAs),
`docs/FIGMA_DESIGN.md` (UI source of truth), and `docs/decisions/`.

## Requirements
- Flutter **3.44.x** (stable) / Dart **3.12.x**

## Setup
```bash
flutter pub get
flutter gen-l10n        # generates lib/l10n/app_localizations*.dart
```

## Run (flavors via --dart-define-from-file)
```bash
flutter run -t lib/main_dev.dart     --dart-define-from-file=config/dev.json     --flavor dev
flutter run -t lib/main_staging.dart --dart-define-from-file=config/staging.json --flavor staging
flutter run -t lib/main_prod.dart    --dart-define-from-file=config/prod.json    --flavor prod
```
> Android product flavors are wired. iOS schemes per flavor must be added in
> Xcode (macOS) — see `docs/PLAN.md`.

## Verify
```bash
flutter analyze     # clean
flutter test        # unit + bidirectional widget tests
```

## Store config / live schema introspection
Store codes are **confirmed**: `eg_en` (en_US, default view) / `eg_ar` (ar_SA),
both **AED** (see `docs/decisions/stores.md`). The app still resolves the
`locale → store_code` mapping dynamically at runtime from `availableStores`.

The agent sandbox can't reach `zoonze.com`, but a **GitHub Actions** runner can,
so introspection runs there:
```bash
# locally, on any network that reaches the origin:
bash tool/introspect.sh        # availableStores + storeConfig + schema + payment-contract check
bash tool/verify_payments.sh   # paymentSession / tabbyConfig shape + a live session
```
Or trigger the **Introspect Live GraphQL** workflow (Actions tab) — it runs
`tool/introspect.sh` and uploads the output + `schema.introspection.json`.

## Project layout
```
lib/
  app/         MaterialApp.router, router, theme (Figma tokens), shell (drawer/nav/footer)
  core/        config · graphql (link chain + resilience) · store (dynamic resolution)
               storage (secure/Hive/prefs) · error · notifications · util · widgets · assets
  features/    catalog · search · cart · auth · checkout (payments) · account · wishlist
               · notifications · diagnostics
  l10n/        app_en.arb · app_ar.arb
config/        dev|staging|prod.json
tool/          introspect.sh · verify_payments.sh
.github/workflows/   ci · release-android · release-ios · introspect
docs/          backend/payment-contract.md · decisions/ · PLAN.md · FIGMA_DESIGN.md
```

## Conventions
Typed everything · repository boundary is sacred · errors are values
(localized `Failure`) · bidirectional by default · no fabricated data · token in
secure storage only · analyzer clean. (See `docs/decisions/architecture.md`.)
