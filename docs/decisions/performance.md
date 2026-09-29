# Decision — Performance polish (Phase 5)

A focused pass; the catalog lists were already lazy, so the win was image memory.

## Applied
- **Image decode sizing.** Every `CachedNetworkImage` / `Image.asset` now decodes
  at the on-screen size (× device pixel ratio), not the source's full resolution
  — the main memory/jank win across product grids:
  - `ProductCard` thumbnail — `memCacheWidth` from a `LayoutBuilder` (exact cell width).
  - PDP gallery — `memCacheWidth` from the screen width.
  - Cart thumbnail — `memCacheWidth` for the fixed 72pt size.
  - Home banner (`Image.asset`) — `cacheWidth` from the screen width.

## Already optimal (verified, left as-is)
- **PLP** uses a lazy `SliverGrid` + `SliverChildBuilderDelegate`; **home** uses
  `ListView.separated` / `GridView.builder`. The framework adds repaint
  boundaries to builder-delegated children by default.
- **Bottom-nav badges** scope rebuilds with `cartControllerProvider.select((s) => s.itemCount)`.
- Screen-level `ListView(...)`s (account, checkout, notifications, etc.) hold a
  small bounded set of children — converting to builders would add complexity
  for no measurable gain.

## Not done (out of app-side scope / low value)
- Home "Featured" uses a `shrinkWrap` `GridView.builder` (builds all featured
  items); the set is small, so left as-is.
- Startup/runtime profiling on a device (DevTools timeline) is a developer step
  on real hardware.

---

# Decision — Image loading (CL042-DEV07, 2026-08-21)

Client report: "Some product images take a few moments to display… we just need
the image to be loaded and ready to display as soon as we open the page."

Four causes, three of them app-side.

## What was actually wrong

1. **Every image was forced through ~1s of dissolve.** `cached_network_image`
   defaults to `fadeInDuration: 500ms` **and** `fadeOutDuration: 1000ms` — the
   placeholder fades *out* over a full second while the image fades in. Neither
   was overridden at any of the 18 call sites, so an image already on disk was
   still visibly veiled. `fadeOutDuration` was the bigger offender of the two,
   and it is the one nobody thinks to set.
2. **The PDP discarded an image it already had.** `/product/:urlKey` carried
   only the url_key, so tapping a card whose bitmap was already decoded showed a
   bare `CircularProgressIndicator` until the entire detail document resolved
   (description, 20 reviews, rating histogram, 8 also-like products, every
   variant) — and only then began fetching the hero.
3. **Nothing was ever pre-warmed.** `precacheImage` appeared nowhere in the
   repo. The hero carousel (5s auto-advance) did not warm the next slide; the
   PLP did not warm the page it had just appended; the 2.6s splash hold did no
   catalog work at all.
4. **The store serves one large derivative for every image role** — backend, see
   below.

## Live measurements (2026-08-21, re-runnable)

```bash
curl -s https://zoonze.com/graphql \
  -H 'Content-Type: application/json' -H 'Store: eg_en' -H 'User-Agent: ZoonzeApp-dev' \
  --data '{"query":"{products(search:\"perfume\",pageSize:3){items{sku image{url} small_image{url} thumbnail{url}}}}"}'
```

`image`, `small_image` and `thumbnail` return **byte-identical URLs** — the same
generated-cache hash `74c1057f7991b4edb2bc7bdaa94de933` for every SKU sampled.
The theme's `view.xml` defines no per-role dimensions, so one derivative serves
all three roles.

| Asset | Bytes | Notes |
|---|---|---|
| `p/i/picnic_blanket_4.png` | 316,421 | 823×823 PNG — also used for a 44pt search row |
| `a/r/armf00365.jpg` | 40,211 | JPEG |

Media headers: `Cache-Control: public, max-age=31536000, immutable`,
`X-Cache: Hit from cloudfront`, `Vary: Origin`. No `Accept`-based WebP
negotiation. `eg_ar` returns the **same** media URL for the same SKU, so image
URLs are store-agnostic and a store switch must **not** clear the image cache.
(The WAF 403s requests with no `User-Agent` — always send one.)

## Applied

- **`ZoonzeImage` (`lib/core/widgets/network_image.dart`) is the only entry
  point for network images.** No bare `CachedNetworkImage` in feature code — a
  house rule, so the defaults cannot creep back in one screen at a time.
  - `fadeInDuration` / `fadeOutDuration` / `placeholderFadeInDuration` are all
    `Duration.zero`. A hard cut reads as "instant"; a dissolve reads as "slow".
    Locked by a test.
  - Decode sizing everywhere (`memCacheWidth` only — never both axes), from an
    explicit width or from layout.
  - Flat placeholder by default; `shimmer: true` only where the placeholder
    genuinely persists (heroes, banners, category/brand tiles). Each `Shimmer`
    runs its own ticker, so a grid of them is waste.
  - `ZoonzeImage.provider()` mirrors what the widget resolves internally
    (octo_image applies `memCacheWidth` via `ResizeImage.resizeIfNeeded`).
    **A pre-warm at a different decode width is a different `ImageCache` key and
    buys nothing** — this is the one way the prefetching silently does nothing.
    `pdpImageWidth()` exists so the PDP hero and its pre-warm cannot disagree.
- **PDP instant hero.** `openProduct()` pre-warms the hero at PDP decode width
  and carries a `ProductPreview` (image/name/brand/price) in go_router's
  `extra`; the loading state is a `ProductDetailSkeleton` that paints those real
  values. Always additive — deep links, push notifications and restored routes
  arrive with no `extra` and fall back to the plain skeleton.
  - The preview price is a listing `price_range` minimum and can differ from the
    selected variant's. It is shown in the **skeleton only**; the loaded PDP
    always prices from its own document. Do not "optimise" it into `_Content`.
- **Bounded prefetch** (`lib/core/util/image_prefetch.dart`): hero next/previous
  slide (2), PDP gallery neighbours (2), also-like rail post-frame (4), top of
  each appended PLP page (6).
  - **Deliberately not prefetched:** the whole PLP grid, every gallery image,
    all brand logos, anything not scrolled toward. Unbounded prefetch spends
    mobile data the user did not agree to spend and evicts what is on screen
    from a finite `ImageCache`.
- **Splash warm-up.** The 2.6s hold now kicks `categoryTreeProvider`,
  `homeConfigProvider` and `heroSlidesProvider` and precaches the first hero
  image. Those three `keepAlive()` — otherwise the autoDispose subscription ends
  with the splash and the result is thrown away. Each still watches
  `activeStoreCode`, so a store switch invalidates them. Fire-and-forget on
  every path: a cold or offline start still leaves the splash on time.
- **`ZoonzeImageCacheManager`** (600 objects / 30 days) replaces
  `DefaultCacheManager`'s 200. One PLP page is 20 images, so a browse session
  used to evict the top of the grid before the user scrolled back to it. Safe
  because media is `immutable` and content-hashed. `flutter_cache_manager` is
  now a direct dependency (importing it transitively trips
  `depend_on_referenced_packages` and fails the analyze gate).
- **`Product.thumbUrl` scaffold** — see "Deferred" below.

## Decisions recorded (not open questions)

- **`PaintingBinding.instance.imageCache` stays at its defaults** (1000 entries /
  100MiB). Decode sizing is now universal, and raising the byte cap risks OOM on
  low-end hardware for no perceptual gain. If DevTools ever shows eviction
  thrash, raise `maximumSize` (entry count, cheap) — never `maximumSizeBytes`.
- **`FetchPolicy.networkOnly` stays.** `cacheAndNetwork` for catalog reads is a
  separate ticket, not a quick win: the normalized cache holds locale-,
  currency- and price-specific data, and CLAUDE.md §3.1 requires a reset on
  store switch, so a cached read after a switch can show Arabic prices under
  English labels. Also, in `graphql_flutter` 5.x `client.query()` returns only
  the *final* result for `cacheAndNetwork`, so flipping the policy inside
  `CatalogRepository._query` would buy nothing — the instant cached paint needs
  two emissions threaded through the repository as a `Stream`, which changes
  every catalog signature and its fakes. Price, stock, cart and checkout stay
  `networkOnly` permanently.
- **`Config.maxNrOfCacheObjects` caps count, not bytes.** 600 × ~40KB ≈ 24MB
  typical; 600 × 316KB ≈ 190MB worst case — reachable only while the backend
  serves 300KB PNGs. Revisit the count once the presets below land.

## Deferred — `small_image` / `thumbnail`

Switching the query field buys **zero bytes today** (identical URLs), so only
the model changed: `Product.thumbUrl` with a `thumbnail => thumbUrl ?? imageUrl`
fallback, which keeps every call site and `FakeCatalogRepository` compiling.

**Resume condition:** re-run the probe above. **If the three cache hashes
differ**, select `small_image { url }` in `lib/features/catalog/data/catalog_queries.dart`
(the hand-written strings — the `.graphql` files and generated `*.graphql.dart`
are not imported by anything and changing them does nothing at runtime), plus
`cart_queries.dart`, `wishlist_queries.dart` and `account_queries.dart`; map it
into `thumbUrl` in `product_mapper.dart`; point the ≤72pt surfaces at
`product.thumbnail`. Note this also breaks the identity the PDP pre-warm relies
on (listing `image` == `gallery[0]`), so re-check `openProduct()` then.

## Backend asks (not app work)

1. **`view.xml` image presets.** Define distinct `product_small_image` (~300px)
   and `product_thumbnail_image` (~120px) and run `bin/magento
   catalog:images:resize`. Largest byte-level win available; verify by getting
   three *different* cache hashes from the probe above.
2. **WebP/AVIF.** Magento 2.4.7+ can emit WebP, or a CloudFront Function can do
   `Accept`-based negotiation. That 316KB PNG is roughly 40KB as WebP.
3. **CloudFront `/media/*`.** Strip `Origin` from the cache key — `Vary: Origin`
   on an immutable public asset fragments the edge for nothing. The first-view
   `Miss` is the latency the client filmed.

A cold start with an empty disk cache on mobile data is still bound by those
three; no app change fixes it. Set that expectation when reporting the ticket.
