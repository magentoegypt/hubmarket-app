# Decision — Guest order tracking

_Added 2026-08-21 — ClickUp **[CL042-DEV18] 86d432wme** ("track my orders")._

## The bug

`/orders` had no auth guard, and `OrdersScreen` unconditionally ran
`AccountQueries.orders` (`customer { orders … }`). Every "Track Order" entry
point routes there — the Order Success CTA, the footer link, the account tile,
the menu drawer, and the `type: 'order'` push deep link.

Guest checkout is a shipped flow, so a guest who placed an order and tapped
**Track Order** sent that query with no bearer. Reproduced against live
(2026-08-21):

```
POST https://zoonze.com/graphql   (Store: eg_en, no Authorization)
{ customer { orders(pageSize:10,currentPage:1,scope:WEBSITE){ total_count } } }

HTTP 403
{"errors":[{"message":"The current customer isn't authorized.",
            "extensions":{"category":"graphql-authorization"}}],"data":{"customer":null}}
```

→ `Failure(FailureKind.auth)` → `errorGeneric` → a full-screen error whose
**Retry could never succeed**. It also tripped `handleSessionExpired()` (and
therefore a `graphqlClientProvider` invalidation) on every attempt, for a
session that never existed.

## The resolution

Guests get real in-app tracking, using **native Magento 2.4.8 queries** — no
custom module, unlike `MagentoEgypt_PaymentGraphQl`. Both were introspected and
probed on the live endpoint:

```graphql
guestOrder(input: OrderInformationInput!): CustomerOrder!   # { number!, email!, lastname! }
guestOrderByToken(input: OrderTokenInput!): CustomerOrder!  # { token! }
```

Both return the **same `CustomerOrder` type** as `customer { orders }.items`, so
the field selection (`AccountQueries._orderFields`), `_parseOrder`, and the whole
Order Detail / Track Order UI are shared verbatim. An unknown order answers
`graphql-no-such-entity` — "We couldn't locate an order with the information
provided." — which the lookup form surfaces through `serverMessageOr`.

### How the app remembers a guest order

`CheckoutController.placeOrder()` persists a `GuestOrderRef`
(`lib/features/account/data/guest_order_store.dart`, hive key `guest_orders`,
newest-first, capped at 10) the moment the order is placed — the only point
where `placeOrder.orderV2.token` **and** the billing email/lastname are both in
hand. Nothing else has to thread the identity: `PlaceOrderResult`,
`CompletePaymentArgs`, and `_goSuccess` are untouched.

The ref stores **no order content** — only the lookup keys. Status, items and
tracking are always re-fetched live, so a guest sees the same freshness a
customer does.

**Token first, email/lastname as fallback.** The token authorizes on its own and
carries no personal data; the email pair is the only key available for an order
the guest typed into the lookup form (or placed on the website).

### A failed lookup is not a deletion

`Failure` carries no error category, so "not found" cannot be told apart from a
transient server error without matching on non-localized message text. Refs that
fail to resolve are therefore **kept** and rendered as a row with Retry /
Remove — a network blip must never silently delete the only record a guest has
of their order. Only the user removes an entry.

### Entry points after the change

| Entry point | Guest | Customer |
|---|---|---|
| Order Success "Track Order" | remembered orders, resolved live | `customer { orders }` |
| Footer "Track Order" | same (the `sales/guest/form/` WebView fallback is gone) | same |
| Account tile / menu drawer / push `type: 'order'` | same | same |
| My Orders ▸ "Track another order" | `/track-order` lookup form | — |

## Also fixed here

- `OrderTrackingScreen` had `order.trackings` but used it only as a boolean
  stage hint, so **Track** showed *less* tracking data than **View Details**. It
  now renders carrier · service, the AWB forced LTR, and a copy action.
- Its two `orderFmtDateTime` calls dropped the locale — Arabic timestamps
  rendered in the default locale.
- `/order-detail` and `/order-tracking` cast `state.extra as CustomerOrder`
  unguarded; `extra` is in-process memory, so a cold start threw. They now
  redirect to `/orders`.

## Known, out of scope

`/complete-payment` still hard-casts `state.extra as CompletePaymentArgs`
(`router.dart`), and its "Pay later" action drops a guest's order identity
(`complete_payment_screen.dart`). Both are payment-retry defects rather than
tracking ones; `GuestOrderStore` now makes them straightforward to fix.
