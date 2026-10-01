# CLAUDE.md — Hub Market customer app (Flutter)

> **Mission:** the Hub Market **customer** app (Android + iOS) — a headless client
> for the multi-vendor marketplace at **hub-market.magento2.click** (Magento Open
> Source 2.4.8-p5 + Vnecoms marketplace). UAE market, **English (LTR) + Arabic
> (RTL)**, **AED**. Design: Figma `rJVCVQdnC59gNbLAWQBZw3` (v3). ClickUp: dev task
> 14zb93nv394 (CL036), QA bugs 14zb93nv6vb (QA01) and 14zb93nv93c (QA02).

This repo started as a copy of `magentoegypt/zoonze-app` @ 8034e97 (the client
allowed reusing the Zoonze codebase). The architecture, conventions and most
features come from there; the Zoonze-specific parts (backend modules, beauty
copy, burgundy brand, N-Genius / Samsung Pay / Apple Pay wiring, Tabby / Tamara,
intro video) have been removed. `docs/zoonze-reference/` keeps a few Zoonze docs
**as reference only**; do not treat their store codes, hosts, payment gateways or
backend modules as Hub Market facts.

## 1. Backend facts (verified 29 Sep 2026)

| Item | Value |
|---|---|
| GraphQL | `POST https://hub-market.magento2.click/graphql` |
| Store views | `en` (default, en_US) · `ar` (ar_SA) — header `Store: <code>` |
| Currency | AED · root category uid `Mg==` · timezone Asia/Riyadh |
| Storefront code | GitHub `magentoegypt/multivendor`, branch **`figma-parity-home`** (local clone `C:\xampp\htdocs\multivendor`) — the reference for how the website builds every page |
| Search | The website searches Algolia (app `HL67ED06DQ`, indices `hubmarket_{en,ar}_{products,categories,pages}`). GraphQL `products(search:)` is answered by **OpenSearch** (backend `AlgoliaVendor` EngineResolverPlugin since e52ba5c27, because Algolia's adapter ignores GraphQL filters), so its ranking can differ. Decision 29 Sep: the app queries Algolia directly for search (`features/catalog/data/algolia/`), GraphQL only as the fallback. The website's key is an Algolia **secured** key (`tagFilters`, `validUntil` = page render + 24 h), so none ships in the app: it comes from `hmAppConfig.algolia` when HubApp answers, otherwise from the storefront page's `window.algoliaConfig` |
| OTP (WhatsApp/SMS) | `customer{Login,Register,ForgotPassword,Checkout}{SendOtp,VerifyOtp}` — verify does **not** return a customer token. WhatsApp **sign-in** therefore uses the SmsExtend REST pair `POST /V1/whatsapp/otp/{send,verify}` (`type: LOGIN`), which does return one; `hmSendWhatsAppCode` / `hmSignInWithWhatsAppCode` take over once HubAppAccount is deployed and its `whatsapp_login` flag is on |
| Payments | `available_payment_methods` is the only source; cash on delivery is confirmed live; Adobe Payment Services + Vault mutations exist; **no** N-Genius `paymentSession`, **no** `tabbyConfig`. The app lists only methods that complete on `placeOrder` (`is_deferred` false) until a gateway is integrated |
| Not in the live core schema (Zoonze had them) | hero slides, home banners/sections, brands, blog, `magentoegypt_beauty_*` config, `free_shipping_subtotal`, `cod_fee`, `is_new_arrival` / `is_bestseller`, `also_like_products`, `rating_histogram`, avatars, `registerDeviceToken`. The HubApp contract now covers some: hero + home sections → `hmAppHome`, brands → `hmBrands`, best sellers → `hmBestSellers`, device tokens → `hmRegisterDevice` |

## 2. Tooling

- `python tool/introspect_to_sdl.py` — refresh `lib/core/graphql/schema.graphql` from the live endpoint.
- `python tool/validate_ops.py` (set `PYTHONIOENCODING=utf-8`) — checks **every** GraphQL operation (`.graphql` files and inline Dart query strings) against the live schema **plus** the Hub Market App contract `lib/core/graphql/hubapp.graphql` (merged the Magento way; `--live-only` checks the live schema alone; `--schema-file lib/core/graphql/schema.graphql` reads the committed SDL instead of the live server, offline). Run it before every push; it must report 0 problems. Its own tests: `python -m unittest discover -s tool -p "test_*.py"`.
- `dart run build_runner build --delete-conflicting-outputs` — graphql_codegen for `lib/**/data/graphql/*.graphql`.
- `python tool/gen_possible_types.py` — regenerates `lib/core/graphql/possible_types.dart` (every interface and union of the live SDL plus the contract, with its implementers). The client's cache needs it: without it a fragment on an interface (`fragment F on ProductInterface`) comes back empty. Run it after refreshing the schema or the contract; the tool tests (CI) fail when it is stale (`--check`).
- `flutter analyze` · `flutter test` · `dart run flutter_launcher_icons` (icons from `assets/branding/`).
- Release readiness: `docs/release/README.md` (status, what the client provides, secrets → workflows, first Android and iOS release, production-domain switch) with the EN/AR store listing, the privacy and data-safety answers, the App Review notes, the deep-link files and the screenshot plan beside it. Keep `ios/Runner/PrivacyInfo.xcprivacy` and `docs/release/privacy-and-data-safety.md` in step. Screenshots: `tool/ios_screenshots.sh` (CI, macOS) and `tool/android_screenshots.sh` (a phone that stays unlocked).
- Never send a GraphQL **mutation** to the live server from tooling or tests — queries and introspection only.
- CI: `build-on-push.yml` runs on every push to main (`[skip ci]` skips it): the gate (analyze, test, the tool tests, `validate_ops.py --schema-file` offline), then the prod APK to Loadly, the signed App Store IPA to TestFlight, an ad-hoc IPA to Loadly (once `IOS_ADHOC_PROFILE_BASE64` exists) and the app bundle to Play internal testing (once the Play secrets exist and the variable `PLAY_AUTO_PUBLISH` is `true`). Builds are numbered by `tool/build_number.sh` (the commit count); the repository variable `DEPLOY_ON_PUSH=false` pauses the store and iOS uploads. `ci.yml` runs the gate on pull requests. `release-*.yml` and `build-ios.yml` are manual. Details: `docs/release/README.md` section 3b.
- The repo is **public**: no signing files in git (`ios/signing/` is ignored). CI decodes them from base64 secrets — `ANDROID_KEYSTORE_BASE64` (+ passwords), `IOS_P12_BASE64` + `IOS_P12_PASSWORD`, `IOS_APPSTORE_PROFILE_BASE64` / `IOS_ADHOC_PROFILE_BASE64`.

## 3. Content is managed in Magento — nothing marketing-related is hard-coded

QA02 requires every banner, block, image and section title to be editable in the
backend. The Home has two modes:
- **Build 2**, when HubApp answers `hmAppConfig`: the admin's layout from `hmAppHome` — ordered sections of 17 types (`HmSectionType`: delivery strip, hero banners, category chips, today's deals, picked for you, featured stores, category rail, bundle deals, CMS promos, best sellers, popular products, top brands, top vendors, new stores, trust row, any CMS block, product list);
- **Build 1** (live today): the storefront CMS blocks `hm_delivery_promise`, `hm_home_promos`, `hm_home_trust` (Content › Blocks), parsed into native widgets by `features/home/domain/home_content.dart`, plus the category tree (Shop by category, one rail per top-level category).

Today's Deals (10b) is built, on `hmDeals`: core GraphQL can't filter or sort on
special prices. Other CMS blocks the app reads: `hm_app_faq` (Help centre FAQ,
the bundled FAQ as fallback), `hm_footer_customer` (the WhatsApp support link)
and `hm_footer_legal` (the legal links).

**HubApp** is built and deployed — magentoegypt/multivendor PR #22, merged into
`figma-parity-home` as `bb1ca0555` on 30 Sep and live on
`hub-market.magento2.click` (Varnish in front, varying on the `Store` header:
public GETs are cached server-side although the client sees `no-store`; watch
`X-Magento-Cache-Debug` for MISS/HIT; `multi.magento2.click` is the uncached
origin). It is a module family: `HubApp` (app settings, Home, deals, best
sellers, bundle deals, brands), `HubAppVendors` (stores, `hm_seller`, other
sellers), `HubAppBundle`, `HubAppReturns`, `HubAppAccount` (store credit, push
devices, WhatsApp sign-in) and `HubAppOrders` (per-store order packages); the
app's copy of the contract is `lib/core/graphql/hubapp.graphql`. The app probes
`hmAppConfig` on each launch and store switch (it also lists which satellites
are enabled, `capabilities`) and falls back to Build 1 when it isn't there. A
deploy means a few minutes of 503s and a first call of 15-25 s while caches
rebuild: the retry and the Retry button are for that. Remote feature flags (`hmAppConfig.features`): `store_credit`,
`returns`, `whatsapp_login`, `push` — an unset flag counts as off. The Figma
section "G · Managed from the backend" shows the admin screens and the full map.

Only the app icon, the native launch screen and interface wording ship with the
app (see Figma G3).

## 4. Brand

Tokens in `lib/app/theme/app_colors.dart`: navy `#0F2144` (primary), logo navy
`#02224D`, orange `#F26522` / `#C2410C` (AA text). Logo + icon are the
client-supplied artwork (traced to vectors in Figma, rendered to
`assets/branding/`). Fonts: DM Sans (text, variable), Tajawal (Arabic) and Playfair
Display (display), as in the Figma; OFL licences in `assets/fonts/licenses/`,
registered by `lib/app/font_licenses.dart`.

Icons are **Lucide**, the set the Figma file draws (`assets/fonts/Lucide.ttf`, ISC licence in
`assets/fonts/licenses/`, named in `lib/app/theme/hub_icons.dart` as `HubIcons.*`; a filled heart or star
stays a Material glyph). Prices drop the decimals of a whole amount ("AED 425"; Arabic reads "425 د.إ", see
`Money.arabic`); a discounted product's old price is always struck through.

**The UI is held to the Figma frames.** `docs/ui-audit.md` is the working guide (how to compare a screen, the
shared widgets `HubTopBar` / `HubChip` / `HubButton` / `HubIconButton` / `ProductCard` / `HubBottomNav`, the
deliberate deviations, what still differs and why); `flutter test --dart-define=UI_AUDIT=true` renders every
screen with the iPhone insets and `python tool/ui_audit/pairs.py en|ar` lays each next to its frame.
The screens have no hamburger menu; a pushed page whose frame shows no tab bar passes `showTabBar: false` to
`HubScaffold`.

## 5. Conventions (kept from the Zoonze base)

Feature-first `data / domain / presentation`; Riverpod for state + DI; go_router;
repositories return domain entities or throw `Failure`; typed GraphQL; images
through `HubImage`; directional layout everywhere (`EdgeInsetsDirectional`,
`AlignmentDirectional`); a language switch is a store switch (locale + `Store`
header + cache reset + router rebuild). No fabricated data — empty sources hide
their section. Small commits; messages end with the Co-Authored-By trailer.

Compile-time backend switches are `BackendCapabilities`
(`lib/core/config/backend_capabilities.dart`): `hubMarket` has
`whatsappOtpLogin: true` and `guestCheckoutOtp: false`; whatever depends on
HubApp follows the run-time probe instead. Push is dormant: no Firebase config
is bundled, the Android manifest removes `POST_NOTIFICATIONS`, and device
registration (`hmRegisterDevice`) waits for FCM and HubAppAccount's `push` flag.
