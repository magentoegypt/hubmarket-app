# Shared links & Android App Links

_Decided 2026-08-22 — ClickUp CL042-DEV10 ("Product link issue")._

**Symptom:** copying a product link in the Android app and reopening it showed
`GoException: no routes for location: https://zoonze.com/uae-en/fragrance/6085010044712.html`.
That was the *app's own* error page, not a storefront 404. Two independent
defects produced it.

## 1. `base_link_url` is the only language-carrying base

`availableStores` (verified live 2026-08-22):

| store_code | locale | `secure_base_url` | `base_link_url` |
|---|---|---|---|
| `eg_en` (default) | `en_US` | `https://zoonze.com/` | `http://zoonze.com/uae-en/` |
| `eg_ar` | `ar_SA` | `https://zoonze.com/` | `http://zoonze.com/uae-ar/` |

`secure_base_url` is identical for both views, so any URL built from it silently
resolves against the **default (English)** store. Only `base_link_url` carries
the language path — and Magento returns it as `http://`, so it must be
TLS-upgraded. Note the path segment (`uae-en`) is **not** the store code
(`eg_en`); never derive one from the other.

**Rule:** every user-facing storefront URL comes from
[`lib/core/store/store_urls.dart`](../../lib/core/store/store_urls.dart)
(`productUrl` / `storeUrl` / `storeBaseUrl`), never from ad-hoc concatenation.
Two share implementations had independently got this wrong — the PDP hardcoded
`https://zoonze.com/<url_key>`, the product card used `secure_base_url`.

## 2. `.html` is mandatory

`urlResolver` against `eg_en`, for `url_key = 6085010044712` (`url_suffix = .html`):

| queried path | result |
|---|---|
| `fragrance/6085010044712.html` | `PRODUCT` |
| `6085010044712.html` | `PRODUCT` |
| `6085010044712` | **null** |
| `uae-en/fragrance/6085010044712.html` | **null** — the store segment must be stripped first |

A suffix-less link 404s on the web *and* cannot be resolved back into the app.
`CatalogRepository._storeRelativePath` already strips the store segment.

## 3. Unmatched locations resolve instead of throwing

`AndroidManifest.xml` claims `zoonze.com` with `autoVerify`, so the OS hands
storefront URLs to Flutter — but no `GoRoute` matches a storefront path, and the
router had no `errorBuilder`. It now routes to
[`DeepLinkResolverScreen`](../../lib/app/deep_link_resolver_screen.dart), which:

1. switches language when the path carries the other view's segment (`/uae-ar/`);
2. resolves the path via `urlResolver` → PDP or PLP, reusing the same helpers as
   the home hero CTAs (`lib/features/catalog/presentation/storefront_links.dart`);
3. opens anything else on our own domain (CMS, `shopbrand`, blog) in the in-app
   `WebViewScreen`;
4. shows a branded not-found only for a foreign host.

It deliberately never hands the URL back to the browser: the app claims the
domain, so that can bounce straight back in.

It also seeds `/home` under the destination, so Back from a cold-start deep link
returns to the app rather than exiting it.

**Cold start waits for the store views.** `bootstrap.dart` fires `loadStores()`
unawaited, and on a warm install the cached views land synchronously — but on a
**fresh** install the list is empty for the first frames. Every step of the
resolution above reads it: which hosts are ours, which language the path segment
belongs to, and which `Store` header `urlResolver` runs under. A `/uae-ar/` link
opened on first launch therefore resolved against the default English store. The
resolver now awaits `StoreController.ensureStoresLoaded()` first, which returns
at once when the views are present, joins the bootstrap call when one is in
flight, and times out (5s) rather than wedging the link if the network is dead.

## 4. The intent filter is scoped

The filter previously claimed **every** `https://zoonze.com/*` path — including
`/media/*`, `/static/*`, `/rest/*` and `/graphql`, none of which the router can
resolve. It is now limited to the storefront root, the `/uae-en` and `/uae-ar`
prefixes, and root-level `.html` rewrites (all three URL shapes exist in
`url_rewrites`), across both `zoonze.com` and `www.zoonze.com`.

The prefixes deliberately omit the trailing slash: `pathPrefix="/uae-en/"` does
not match a shared `https://zoonze.com/uae-en`, which Magento serves via a
redirect. The storefront root resolves to the app's Home screen rather than a
WebView of the home page — `urlResolver` has no entity for it.

## Installed → app, not installed → browser

This is stock Android App Link behaviour and needs no app-side branch: a
verified link opens the app when it is installed, and nothing claims the URL
when it isn't, so the browser takes it.

`assetlinks.json` **is** published, on both `zoonze.com` and `www.zoonze.com`,
for `com.zoonze.shop` with SHA-256 `C0:0C:62:B4:…:69:6B:83` — the **Play**
app-signing key, not the upload key in the release notes. Release builds
therefore verify.

`.dev` / `.staging` builds can never verify: different `applicationId`, and
signed with the debug key. Force an intent at them for testing with
`am start … -p com.zoonze.shop.dev`, or approve the domains locally with
`pm set-app-links --package com.zoonze.shop.dev 2 zoonze.com www.zoonze.com`.

## iOS universal links

iOS needs two things Android does not, and **neither is done** — today an
`https://zoonze.com/…` link always opens Safari, installed or not.

**1. The AASA file is not served.** `https://zoonze.com/.well-known/apple-app-site-association`
**301s to `/uae-en/`** (Magento's store-code rewrite swallows the extension-less
path). Apple does **not** follow redirects when fetching it, so this is a real
server change, not a file copy. `assetlinks.json` escapes the same rewrite only
because of its `.json` extension.

Ready-to-publish content: [`docs/backend/apple-app-site-association`](../backend/apple-app-site-association).
Serve it at that exact path on **both** `zoonze.com` and `www.zoonze.com`, as
`application/json`, no extension, no redirect. Its `components` mirror the
Android intent filter (root, `/uae-en*`, `/uae-ar*`, `/*.html`; `/media`,
`/static`, `/pub`, `/rest`, `/graphql` excluded) so both platforms claim the
same URL set.

**2. The entitlement is staged, not active.** `com.apple.developer.associated-domains`
sits commented out in [`ios/Runner/Runner.entitlements`](../../ios/Runner/Runner.entitlements)
with an ordered runbook, exactly as the Apple Pay entitlement does and for the
same reason: an existing provisioning profile never picks up a new capability,
so declaring it early breaks local signing and — because CI re-signs from the
**profile** — would ship a build silently without it. Neither committed profile
carries the capability today (checked 2026-08-22).

Enabling it needs the App ID capability plus a regeneration of **both**
`ios/signing/*.mobileprovision`. `tool/ios_appstore_build.sh` then fails the
build if the key is declared but missing from the signed app, so the silent
failure mode is closed.

Nothing in Dart changes: `FlutterDeepLinkingEnabled` is already true, and
`DeepLinkResolverScreen` is platform-agnostic.

**Checking either platform:** `bash tool/verify_applinks.sh` — curl-only, no Mac
or device needed. As of 2026-08-22 it reports Android OK on both hosts and iOS
failing on the 301.

## Open owner dependency

**Android: none.** `assetlinks.json` is published on both hosts and matches the
Play app-signing key. Earlier notes (including [release.md](release.md)) called
this an open task; it is not, verified live 2026-08-22.

**iOS: two, both external.** Serve the AASA file (server), then enable Associated
Domains on the App ID and regenerate both provisioning profiles (Apple Developer
portal). See "iOS universal links" above.

See "iOS universal links" above for the iOS equivalent. §1–2 (URL shape) apply to
both platforms; §3 (in-app routing) is platform-agnostic and already done.
