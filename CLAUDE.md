# CLAUDE.md — Hub Market customer app (Flutter)

> **Mission:** the Hub Market **customer** app (Android + iOS) — a headless client
> for the multi-vendor marketplace at **hub-market.magento2.click** (Magento Open
> Source 2.4.8-p5 + Vnecoms marketplace). UAE market, **English (LTR) + Arabic
> (RTL)**, **AED**. Design: Figma `rJVCVQdnC59gNbLAWQBZw3` (v3). ClickUp: dev task
> 14zb93nv394 (CL036), QA bugs 14zb93nv6vb (QA01) and 14zb93nv93c (QA02).

This repo started as a copy of `magentoegypt/zoonze-app` @ 8034e97 (the client
allowed reusing the Zoonze codebase). The architecture, conventions and most
features come from there; everything Zoonze-specific (backend modules, beauty
copy, burgundy brand, N-Genius wiring, intro video) is being removed or gated.
`docs/` still holds the Zoonze docs **as reference only** — do not treat their
store codes, hosts, payment gateways or backend modules as Hub Market facts.

## 1. Backend facts (verified 29 Sep 2026)

| Item | Value |
|---|---|
| GraphQL | `POST https://hub-market.magento2.click/graphql` |
| Store views | `en` (default, en_US) · `ar` (ar_SA) — header `Store: <code>` |
| Currency | AED · root category uid `Mg==` · timezone Asia/Riyadh |
| Storefront code | GitHub `magentoegypt/multivendor`, branch **`figma-parity-home`** (local clone `C:\xampp\htdocs\multivendor`) — the reference for how the website builds every page |
| Search | Algolia app `HL67ED06DQ`, indices `hubmarket_{en,ar}_{products,categories,pages}`; the website renders results server-side through `algoliasearch-adapter-magento-2`, so `products(search:)` returns the same ranking |
| OTP (WhatsApp/SMS) | `customer{Login,Register,ForgotPassword,Checkout}{SendOtp,VerifyOtp}` — verify does **not** return a customer token |
| Payments | `available_payment_methods` is the only source; cash on delivery is confirmed live; Adobe Payment Services + Vault mutations exist; **no** N-Genius `paymentSession`, **no** `tabbyConfig` |
| Not in the schema (Zoonze-only) | hero slides, home banners/sections, brands, blog, `magentoegypt_beauty_*` config, `free_shipping_subtotal`, `cod_fee`, `is_new_arrival` / `is_bestseller`, `also_like_products`, `rating_histogram`, avatars, `registerDeviceToken` |

## 2. Tooling

- `python tool/introspect_to_sdl.py` — refresh `lib/core/graphql/schema.graphql` from the live endpoint.
- `python tool/validate_ops.py` (set `PYTHONIOENCODING=utf-8`) — checks **every** GraphQL operation (`.graphql` files and inline Dart query strings) against the live schema. Run it before every push; it must report 0 problems.
- `dart run build_runner build --delete-conflicting-outputs` — graphql_codegen for `lib/**/data/graphql/*.graphql`.
- `flutter analyze` · `flutter test` · `dart run flutter_launcher_icons` (icons from `assets/branding/`).
- Never send a GraphQL **mutation** to the live server from tooling or tests — queries and introspection only.

## 3. Content is managed in Magento — nothing marketing-related is hard-coded

QA02 requires every banner, block, image and section title to be editable in the
backend. Today the Home reads:
- storefront CMS blocks `hm_delivery_promise`, `hm_home_promos`, `hm_home_trust` (Content › Blocks), parsed into native widgets by `features/home/domain/home_content.dart`;
- categories and products from the catalogue (Shop by category, one rail per top-level category, Today's Deals = live special prices).

Planned backend module (not built yet): **`MagentoEgypt_HubApp`** — Home layout
registry (section type, EN/AR titles, source, limit, dates, audience, order) +
app settings (search hint, trust items, contact/WhatsApp, force-update,
maintenance, feature flags) exposed as GraphQL `appHome` / `appConfig`, plus
resolvers for Hero Banner slides (existing `MagentoEgypt_HeroBanner` table),
public vendor lists, best sellers, bundles and MGS brands. The Figma section
"G · Managed from the backend" shows the admin screens and the full map.

Only the app icon, the native launch screen and interface wording ship with the
app (see Figma G3).

## 4. Brand

Tokens in `lib/app/theme/app_colors.dart`: navy `#0F2144` (primary), logo navy
`#02224D`, orange `#F26522` / `#C2410C` (AA text). Logo + icon are the
client-supplied artwork (traced to vectors in Figma, rendered to
`assets/branding/`). Fonts: Playfair Display (display), Inter/Cairo bundled today
— Figma uses DM Sans + Tajawal (swap pending).

## 5. Conventions (kept from the Zoonze base)

Feature-first `data / domain / presentation`; Riverpod for state + DI; go_router;
repositories return domain entities or throw `Failure`; typed GraphQL; images
through `HubImage`; directional layout everywhere (`EdgeInsetsDirectional`,
`AlignmentDirectional`); a language switch is a store switch (locale + `Store`
header + cache reset + router rebuild). No fabricated data — empty sources hide
their section. Small commits; messages end with the Co-Authored-By trailer.
