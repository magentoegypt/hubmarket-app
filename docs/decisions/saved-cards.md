# Decision: saved cards (CL042-DEV25)

**Status:** Accepted (owner confirmed Magento Vault + checkout & account scope, 2026-08-28).
**Contract:** `docs/backend/payment-contract.md` §④ — where the two differ, the contract wins.
**Scope:** N-Genius cards only. Tabby, Apple Pay and Samsung Pay are untouched.

---

## 1. The app cannot own this

N-Genius saved cards are gateway tokens. The Android SDK's `SavedCardPaymentRequest`
accepts only `gatewayAuthorizationUrl`, `payPageUrl` and an optional CVV (read off
`payment-sdk:5.2.3` with `javap`) — the card itself must already be attached, server-side,
to the N-Genius order. iOS is the same shape: `NISdk.launchSavedCardPayment` takes the
decoded `OrderResponse`, whose `savedCard` the backend populated.

So the app never holds a PAN, a CVV or a `cardToken`. It chooses a card, offers the save
opt-in, and routes the SDK. Everything else is Magento's.

## 2. Magento Vault, not a bespoke token store

The alternative was a `savedCards` / `deleteSavedCard` pair of custom resolvers with their
own table. Vault won on three counts:

- **Half of it is already deployed.** `customerPaymentTokens`, `deletePaymentToken` and
  `VaultTokenInput` are live on zoonze.com today, so the read/delete path and the whole
  Payment Methods screen could be built and tested against the real schema now.
- **Parity.** A card saved in the app shows up on the website, which is what a customer
  expects and what a bespoke store cannot give.
- **Conventions the backend already knows.** `is_active_payment_token_enabler` is
  Braintree's field name; `ngeniusonline_vault` + `VaultTokenInput` is exactly how
  `payflowpro_cc_vault` works. Nothing here is a Zoonze invention.

The cost is real and belongs to the backend: vendor module 1.1.7 is HPP-only and not
vault-aware, so making it write vault rows is the bulk of the work.

## 3. The vault method is folded into the card row

`ngeniusonline_vault` arrives in `available_payment_methods` like any other method — the
app hardcodes nothing — but it is **not** drawn as its own row. `CheckoutState.
visiblePaymentMethods` drops it and `SavedCardPicker` renders the stored cards *inside* the
"Visa & MasterCard" row, so a shopper with four cards still sees five payment options, not
nine, and `_payRank` needs no rework.

Two consequences worth stating:
- `CheckoutState.isRowSelected` keeps the card row lit while a saved card is chosen, because
  the selected *method* is then the vault code.
- The fold only happens when there is a card row to fold into. A store that somehow offers
  the vault code alone still shows it — otherwise its saved cards would be unreachable.

`isCardVault` is `ngenius` **and** `vault` on the separator-stripped code, so
`payflowpro_cc_vault` (a real core method) cannot be mistaken for ours.

## 4. Which SDK screen opens is decided by the order, not by an argument

The `pay` channel gains **no** field. Android checks for a `savedCard` node in the order
JSON it already parses for `_links`; iOS checks `order.savedCard`. The order is the thing
both SDKs actually read, so a channel argument could only ever disagree with it — and the
disagreement would open a blank card form for a tokenised order.

No CVV crosses the channel either: recapture is the SDK's own screen (Android
`SavedCardPaymentState.CaptureCvv`). An unreadable or `savedCard`-less order falls back to
the ordinary card form, which is the recoverable direction.

## 5. Degradation is the whole point of the shape

Nothing here breaks a store without §④:

| Missing | Behaviour |
|---|---|
| Vault rows for N-Genius | Empty list → no picker, no cards on the account screen, current checkout unchanged |
| `ngeniusonline: { is_active_payment_token_enabler }` | `setPaymentMethod` retries bare, the box unticks itself, **the order still goes through** |
| `ngeniusonline_vault` method | No cards offered even if tokens exist — never offer a card that would dead-end at place-order |
| `SetOrderPaymentMethodInput.public_hash` | A separate document is only sent when a card is picked, so the existing retry screen is untouched |

The one place that deliberately does **not** fall back is a saved-card *selection*: dropping
the hash would place the order against an unspecified token. It throws instead.

`savedCardsProvider` swallows its errors (guests get a hard 403 from
`customerPaymentTokens`) — the same "degrade, never fabricate" policy as
`fetchPaymentSession` / `fetchTabbyConfig`.

## 6. Bidirectional + expiry

Card numbers and expiry dates render `TextDirection.ltr` inside the RTL layout, like prices.
An expired card is shown, labelled, and not selectable rather than hidden — a customer who
can't find their card assumes the app lost it. A card with *no* stored expiry counts as
usable: letting the gateway decline it beats hiding it on a guess.

## 7. Open items

1. **Backend §④** — the blocker. Nothing is user-visible until vault rows exist.
2. **`docs/backend/ngenius-graphql-session.md` must be deployed first.** Saved cards ride
   the same session; if `paymentSession` still answers `FAILED` for GraphQL-placed orders,
   this cannot be tested at all.
3. **Device verification** — Android saved-card screen + CVV recapture; iOS
   `launchSavedCardPayment` (signature confirmed against the pinned `NISdk` **v6.0.1** tag,
   but never compiled here — no Pods on the Windows dev box).
4. **Brand marks.** Saved-card rows use a neutral Material card icon; if scheme logos are
   wanted they go in `assets/payments/` alongside the wallet marks.
