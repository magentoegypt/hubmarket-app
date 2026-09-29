# Decision — Store views & dynamic resolution

_Last updated: 2026-06-27 — store codes, catalog modeling, and the payment
contract all re-confirmed against the live endpoint (Introspect run #4)._

## ✅ Confirmed values (live `availableStores`, 2026-06-27)

Discovered via the **Introspect Live GraphQL** GitHub Actions workflow
(`tool/introspect.sh`, header-less `availableStores`):

| Value | Confirmed |
|---|---|
| English store_code | **`eg_en`** (locale `en_US`, **default view**) |
| Arabic store_code | **`eg_ar`** (locale `ar_SA`) |
| Default view | **`eg_en`** → first launch is **English** |
| Currency | **AED** (base + display, both views) |
| Base URL | `https://zoonze.com/` (secure); media `https://zoonze.com/media/` |
| Link URL (storefront) | `base_link_url` = `http://zoonze.com/uae-en/` · `http://zoonze.com/uae-ar/` |

> ⚠️ **`secure_base_url` drops the language; `base_link_url` keeps it.** Both
> store views report the same `secure_base_url` (`https://zoonze.com/`), but the
> PWA storefront serves each view under a **path prefix** (`/uae-en/`,
> `/uae-ar/`) exposed only via **`base_link_url`** (comes back as `http://` —
> upgrade to `https`). Building a per-locale content URL (CMS pages) from
> `secure_base_url` sends the Arabic slug to the default English store → the
> storefront's client-side **404**. The footer WebView (`_openCms`) therefore
> builds from `base_link_url`. `StoreView.baseLinkUrl` carries it.

> The codes are `eg_en` / `eg_ar` (a store-group naming artifact) — **not**
> `uae-*`. Sending an unknown code makes Magento reject the whole request
> (`Requested store is not found`), so `availableStores` must be queried with
> **no `Store` header** (default view) for discovery. `config/*.json`,
> `AppConfig` defaults, and the tool scripts are set to these values.

## ✅ Also verified live (Introspect run #4, 2026-06-27)

The same run exercised the app's real queries and the payment module — all
match the code already in the repo, so no changes were needed:

- **Catalog is properly modeled** (resolves Open Q §5): `categoryList` returns
  real categories with counts — Fragrance (737), Skincare (247), New Arrivals
  (120), Bestsellers (35), Makeup (10), plus not-in-menu Clearance/Bundle Sets.
  `products(search:)` returns real SKUs with `price_range` in **AED** and
  `stock_status`. `include_in_menu` comes back as **Int `1`/`0`** (handled by
  `_asBool`), and `base_media_url` is **`http://`** (upgraded by `httpsMediaUrl`).
- **Payment contract matches `docs/backend/payment-contract.md`** (Open Q §2):
  `paymentSession(order_number, email, lastname, token)`, `tabbyConfig()`,
  `SetOrderPaymentMethodInput { email, lastname, order_number, payment_method,
  token }`; enums `PaymentGateway [NGENIUS, TABBY]`, `PaymentSessionStatus
  [READY, PENDING, REJECTED, FAILED]`, `TabbyProductType [INSTALLMENTS,
  PAY_LATER, CREDIT_CARD_INSTALLMENTS]`; `PaymentSessionData { key, value }`.
- The full schema was uploaded as the run's **`introspection`** artifact
  (`schema.introspection.json`) — convert to SDL for Phase 1 codegen when needed.

## Approach: resolve, don't hardcode
Per owner: the app **does not hardcode** store codes. It bootstraps with a
default code (`BOOTSTRAP_STORE_CODE` = `eg_en`), queries
`availableStores(useCurrentGroup: false)` at runtime, and derives the
authoritative `locale → store_code` map, **default view**, and **currency** from
the response (`StoreController`, `lib/core/store/`). The result is cached in Hive
for subsequent launches; the provisional codes in `config/*.json` are only a
first-launch fallback.

The active store code drives the GraphQL `Store` header on every request
(`StoreHeaderLink`). A language switch is atomic: persist locale → reset the
GraphQL client/cache → rebuild Directionality + theme.

## How discovery is run
`zoonze.com` is unreachable from the agent sandbox (egress policy), but the
**GitHub Actions runner can reach it**. The `Introspect Live GraphQL` workflow
(`.github/workflows/introspect.yml`) runs `tool/introspect.sh` against the live
endpoint and uploads the output + `schema.introspection.json`. Re-run it (or
`bash tool/introspect.sh` on any networked machine) to refresh these values or
to regenerate the schema for Phase 1 codegen.
