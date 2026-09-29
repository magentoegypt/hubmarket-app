# App Store listing copy — English (v1.0.0)

Paste-ready copy for the App Store Connect "Prepare for Submission" page.
Character counts are against Apple's limits and were checked at time of writing.

Everything here describes functionality that exists in the shipped app and
catalog content confirmed against the live `zoonze.com` backend. Nothing is
aspirational — Apple rejects unsubstantiated claims, and copy that promises a
feature the reviewer can't find is a common rejection reason.

---

## Subtitle (30 max)

> Beauty, Fragrance & Skincare

`27 chars`

---

## Promotional Text (170 max)

Editable any time without submitting a new build — use it for campaigns.

> Shop 1,700+ fragrances plus skincare, makeup and hair care. New arrivals
> weekly, bestsellers, and daily deals — delivered across the UAE.

`139 chars`

---

## Keywords (100 max, comma-separated, no spaces)

> perfume,fragrance,skincare,makeup,cosmetics,beauty,hair,serum,oud,uae,dubai,gift,arabic

`87 chars`

Notes:
- Don't repeat words already in the app name or subtitle — Apple indexes those
  separately, so repeating wastes the 100 characters.
- No spaces after commas; each space costs a character.

---

## Description (4000 max)

> **Zoonze — beauty, fragrance and skincare, delivered across the UAE.**
>
> Browse a catalog of more than 2,300 products from the brands you already
> know, with prices in AED and a checkout built for the UAE.
>
> **A real fragrance collection**
> Over 1,700 fragrances — eau de parfum, eau de toilette, and pure parfum for
> women and men. Filter by brand, price, or concentration to find the one
> you're looking for instead of scrolling forever.
>
> **Skincare, makeup and hair care**
> Serums, moisturisers, cleansers and treatments across 475+ skincare
> products, plus makeup and a growing hair care range.
>
> **Find things quickly**
> - Search the full catalog by product or brand
> - Browse by category, or jump straight to a brand from the A–Z brand directory
> - Filter and sort any listing by price, rating, discount and more
> - New Arrivals and Bestsellers, updated as stock changes
> - Deals of the Day for time-limited offers
>
> **Product pages with the details that matter**
> Full image galleries, descriptions, size and variant options, live stock
> status, and customer ratings and reviews where shoppers have left them.
>
> **Save what you like**
> Add products to your wishlist and come back to them later. Your wishlist and
> cart stay with your account, so they're there when you switch devices.
>
> **A checkout that fits the UAE**
> - Prices in AED throughout — no conversion surprises
> - Address book with all seven emirates
> - Cash on delivery available
> - Free delivery over AED 150
> - Track your order from confirmation to arrival
>
> **English and Arabic**
> Switch between English and Arabic at any time. The whole app — not just the
> labels — flips to a proper right-to-left layout in Arabic, with product
> names, categories and prices served in the language you chose.
>
> **Your account**
> Order history and order tracking, saved addresses, profile settings, and
> notifications for order updates. Browse and fill a cart without an account;
> sign in when you're ready to check out.
>
> Zoonze ships across the United Arab Emirates.
>
> Support: [SUPPORT_URL]
> Privacy Policy: [PRIVACY_URL]

`~2,150 chars` — comfortably inside the 4,000 limit.

---

## Fields you still need to supply

These can't be derived from the codebase:

| Field | Notes |
|---|---|
| **Support URL** | Required. A real, reachable page — e.g. `https://zoonze.com/uae-en/contact`. Apple checks it loads. |
| **Marketing URL** | Optional. `https://zoonze.com/uae-en/` |
| **Privacy Policy URL** | Required, and also required by the App Privacy section. |
| **Copyright** | e.g. `2026 Zoonze` |
| **App Review contact** | First name, last name, phone, email. |
| **Demo account** | "Sign-in required" is ticked on the submission page, so Apple needs a working email + password for a real Zoonze customer account. Create a throwaway one and put it in the Sign-In Information fields. |

---

## Claims deliberately left out

Written down so nobody adds them back without checking:

- **"Pay in 4 / Tabby / instalments."** The `tabbyConfig` GraphQL query returns
  a 503 on production (the resolver errors; `storeConfig` and `categories` on
  the same endpoint are fine). The app hides the promo when the config is
  absent, so a reviewer would not see any instalment option. Once the backend
  resolver is fixed and Tabby returns from `available_payment_methods`, add it
  to the checkout bullet list and to Keywords (`tabby`, `installments`).
- **Card payment specifics.** Cash on delivery is confirmed working end-to-end
  on a real order. The N-Genius card path is implemented but wasn't verified
  live, so the copy says "cash on delivery available" rather than listing card
  brands.
- **Product counts as marketing superlatives.** The numbers used (1,700+
  fragrances, 475+ skincare, 2,300+ total) come from live category counts
  queried on 2026-07-29 — root category `product_count` was 2,347, Fragrance
  1,796, Skincare 475. They're stated as round approximations below the true
  figure so they stay true as the catalog moves.
