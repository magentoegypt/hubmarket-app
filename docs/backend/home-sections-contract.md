# Home sections — GraphQL contract

The 2026-07-13 home redesign (see [FIGMA_DESIGN.md](../FIGMA_DESIGN.md)) adds six
sections that mirror the live `zoonze.com` home. The Flutter app renders each
**strictly from the backend** and hides it when the source is absent (the repo's
"no fabricated data / degrade gracefully" rule). This file records which GraphQL
each section consumes.

The backend (`MagentoEgypt_Beauty`) now exposes **dedicated home queries** for
the content sections, alongside the `storeConfig.magentoegypt_beauty_config` bag
(`{ path, value }` list) that carries the on/off toggles + the countdown promo.
Section on/off is gated by the `general/enable_<section>` flags (absent → on).
Every content query returns `[]` when a section is toggled off or empty — that's
normal; the app skips it rather than erroring. All queries are **store-scoped**
(the client sends the `Store` header; `eg_ar` lays out RTL).

## Status per section

| Section | App source | Status |
|---|---|---|
| Shop by Category | **`shopByCategories`** (curated tile grid) | ✅ renders |
| Limited-Time Offer (countdown) | `deals/countdown_*` config keys | ✅ renders |
| Deals of the Day | deals category, resolved by `deals/category_id` (`products`) | ✅ renders |
| Skincare / Makeup banners | **`promoSplitBanners`** (2-banner block) | ✅ renders |
| Special Offer | `offer/*` (`magentoegypt_beauty_offer_*`) | ✅ renders |
| Exclusive Offers | **`homeBanners`** (3-banner block) | ✅ renders |
| Why Shoppers Trust | **`homeReviews(pageSize, minRating)`** | ✅ renders |
| The Zoonze Journal | **`blogPosts(pageSize: 3)`** (Mirasvit `mfblog`) | ✅ renders |

## Dedicated home queries (verified live, store `eg_en`, 2026-07-14)

Wired in `lib/features/catalog/data/home_sections_provider.dart`:

```graphql
shopByCategories  { label category_uid url image position }       # 6 → Shop by Category
promoSplitBanners { eyebrow title cta_label cta_url image_url }   # 2 → editorial banners
homeBanners       { title cta_label description image_url cta_url } # 3 → Exclusive Offers
homeReviews(pageSize: 3, minRating: 3) { author quote rating product_name product_uid }
```

Field mapping the app uses:
- **shopByCategories** → `label` (tile caption), `image` (the circle), ordered by
  `position`; `category_uid` routes straight to the PLP, with `url` as the
  fallback via `openStorefrontUrl`.
- **promoSplitBanners** → eyebrow ("SKINCARE"), title ("Bare Skin, Better"),
  `cta_label` → the "Shop Now" pill, `cta_url`, `image_url`.
- **homeBanners** → `title` → the big discount ("25% OFF"), `cta_label` → the
  white category pill ("Skincare"), `description` → the terms ("on your first
  order"), over `image_url`; `cta_url` is the link.
- **homeReviews** → `author`, `quote`, `rating` (gold stars), `product_name`.
  `product_uid` is base64 of the product id → `products(filter:{uid:{eq}})` / PDP
  (not currently linked; the card shows the product name as plain text per Figma).

Image URLs mostly come back absolute (`https://zoonze.com/media/magentoegypt/…`);
`resolveMediaUrl` passes those through. Two relative shapes also occur and the
leading slash decides the base:

| Backend value | Resolved against | Seen in |
|---|---|---|
| `default/promo.png` | the store **media base** | `deals/countdown_image` |
| `/media/catalog/a.webp` | the store **root** | `shopByCategories` (store `eg_ar`) |

Joining a root-relative `/media/…` onto the media base would duplicate the
`/media/` segment and 404, so `resolveMediaUrl` treats it as origin-relative.

CTA URLs are full storefront links resolved in-app by `openStorefrontUrl` →
`urlResolver` (category → PLP, product → PDP).

> **`shopByCategories` labels are live admin config, not category names.** They
> were re-edited mid-session on 2026-07-17 (tile 0 went "Lipsticks" → "Lips";
> the `eg_ar` labels went English → translated, e.g. `الشفاه`, `العطور`). The
> app renders `label` verbatim, so whatever admin sets is what ships — don't
> hardcode or "correct" these app-side. Verified on-device in both views.

> **Note:** the `homeReviews` feed currently carries ~16 **seeded test reviews**;
> they'll be removed before launch, after which it shrinks to the genuine few.
> The app caps the rail at `pageSize: 3, minRating: 3`.

## The Zoonze Journal (`blogPosts`)

Wired in `lib/features/catalog/data/blog_posts_provider.dart`. This **exact** field
set resolves — an earlier query with `short_content` / `featured_list_image` 500'd;
the working contract is:

```graphql
query HomeBlog {
  blogPosts(pageSize: 3) {
    total_count
    items {
      post_id
      title
      post_url                # absolute, store-prefixed (…/uae-en/blog/post/…)
      publish_time
      first_image             # featured image, else first <img> in body — HTTPS
      short_filtered_content  # excerpt (HTML — Page-Builder-prefixed <style> block; strip it)
    }
  }
}
```

Store-scoped: `Store: eg_en` → English posts, `Store: eg_ar` → Arabic; returns
`[]` when none. `first_image` comes back HTTPS (no mixed content). The excerpt's
leading `<style>…</style>` block is stripped by the app before display. "See More"
opens the store-prefixed `/blog` index (derived from a post URL) in the web view;
each card opens `post_url` in the web view.
