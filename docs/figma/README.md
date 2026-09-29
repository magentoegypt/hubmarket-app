# Figma screen reference

Reference PNGs of every app screen, exported from the Figma design file
(`lxyvR0z3xERp8lw8IlPTlH`) for screen-by-screen comparison against the Flutter
build.

## How they get here

The build/agent sandbox **cannot reach `figma.com`** (egress policy, same as
`zoonze.com`), so the PNGs are exported in CI:

1. Add a repo secret **`FIGMA_TOKEN`** — a Figma *personal access token*
   (Figma → Settings → Account → Personal access tokens).
2. Run the **“Figma export”** GitHub Action (Actions tab → *Figma export* →
   *Run workflow*).
3. It runs `tool/figma_export.sh`, which calls the Figma Images API and commits
   the PNGs into this folder (`docs/figma/*.png`), and also uploads them as a
   run artifact.

To export locally instead: `FIGMA_TOKEN=<token> bash tool/figma_export.sh`.

## Screens (EN frames)

| File | Screen | Node |
|------|--------|------|
| `01-splash-launch.png` | Splash — Launch | `52:2` |
| `02-splash-welcome.png` | Splash — Welcome | `54:2` |
| `03-sign-in.png` | Sign In | `59:2` |
| `04-sign-up.png` | Sign Up | `59:49` |
| `05-forgot-password.png` | Forgot Password | `60:29` |
| `06-home.png` | Home — UAE / EN | `2:2` |
| `07-menu-drawer.png` | Menu Drawer | `178:2` |
| `08-categories.png` | Categories | `57:2` |
| `09-search.png` | Search | `58:2` |
| `10-search-results.png` | Search Results | `58:78` |
| `11-filters-sheet.png` | Filters (Sheet) | `68:2` |
| `12-plp-fragrance.png` | PLP — Fragrance | `32:2` |
| `13-pdp.png` | PDP — Coco Mademoiselle | `34:2` |
| `14-wishlist.png` | Wishlist | `55:2` |
| `15-cart.png` | Cart | `38:2` |
| `16-cart-empty.png` | Cart — Empty | `66:70` |
| `17-checkout.png` | Checkout | `40:2` |
| `18-order-success.png` | Order Success | `60:51` |
| `19-my-orders.png` | My Orders | `62:2` |
| `20-order-tracking.png` | Order Tracking | `63:2` |
| `21-my-account.png` | My Account | `42:2` |
| `22-saved-addresses.png` | Saved Addresses | `64:2` |
| `23-add-address.png` | Add Address | `40:9` |
| `24-notifications.png` | Notifications | `65:53` |
| `25-help-faq.png` | Help & FAQ | `66:2` |
| `26-edit-profile.png` | Edit Profile | `111:2` |
| `27-brands.png` | Our Brands (Explore Brands) | `420:2` |

> The Arabic/RTL mirrors live under the `140:*` / `186:*` node ranges in the
> same file; add them to `tool/figma_export.sh` if you want them exported too.
> The **Our Brands** screen is the full directory the home `explore-brands`
> SEE MORE routes to (live source `/uae-en/shopbrand/`): branded ZOONZE header,
> "Search a brand" field, A–Z filter chips, and a lettered 2-column grid of real
> brand logos. Its AR/RTL mirror is node `450:2` (outside the `140:*` range).
