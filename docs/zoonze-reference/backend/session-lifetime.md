# Customer Session Lifetime — Magento Backend Contract

> **Ticket:** [CL042-DEV20 `86d433b6p`](https://app.clickup.com/t/86d433b6p) — client request [`86d433a6g`](https://app.clickup.com/t/86d433a6g): *"The login time is way too short, we need the customer to stay logged in for a longer period."*
>
> **Status:** **§2 applied 2026-08-26** — Customer Token Lifetime is set to `720` (30 days) in admin, with
> *Use system value* unchecked. The app-side hardening in §4 shipped in the same ticket. §5 remains an
> optional follow-up.
>
> Owner: **Magento / platform team**. Endpoint: `https://zoonze.com/graphql`.

---

## 1. Root cause

`generateCustomerToken` issues a bearer whose lifetime is set by **`oauth/access_token_lifetime/customer`**
— *Stores → Configuration → Services → OAuth → Access Token Expiration → **Customer Token Lifetime (hours)***.

**Magento ships this at `1` hour.** Expiry is evaluated per request (`Magento\Webapi\Model\Authorization\TokenUserContext`
compares the token row's `created_at` against the configured TTL), so an hour after signing in every call comes
back as a `graphql-authorization` error / *"Consumer key has expired"*, and the app correctly drops to guest.

**The app cannot extend this.** Magento GraphQL has no refresh-token mutation — `generateCustomerToken` and
`revokeCustomerToken` are the whole API. There is no client-side fix; the TTL is the fix.

---

## 2. The change — ✅ applied 2026-08-26

Set via *Stores → Configuration → Services → OAuth → Access Token Expiration* →
**Customer Token Lifetime (hours) = `720`**, *Use system value* unchecked. Admin Token Lifetime left on
the system value (`4`). Commands below are the CLI equivalent, kept for reproducing this on another
environment.

Confirm the current value first, so we know the 1-hour default is what customers are hitting:

```
bin/magento config:show oauth/access_token_lifetime/customer
```

Then set it to **720 hours (30 days)** — agreed with the owner as the target session length:

```
bin/magento config:set oauth/access_token_lifetime/customer 720
bin/magento cache:flush
```

Notes:

- **Nobody is forced to re-login.** Because the TTL is applied at request time against `created_at`, raising it
  retroactively extends tokens that were already issued. Customers currently signed in stay signed in.
- **Scope is global** (`default` scope). The path is not store-view-scoped, so one set covers `uae-en` and `uae-ar`.
- **Housekeeping:** the `outdated_authentication_tokens` cron (`Magento\Integration\Cron\CleanExpiredTokens`)
  prunes `oauth_token` rows once they pass the TTL. At 30 days the table holds ~30× more live customer rows than
  at 1 hour. That is small, but confirm the cron group is running.
- **Empty = no expiry at all** on this instance — the admin field states *"We will disable this feature if the
  value is empty."* We deliberately did **not** use that: an explicit `720` keeps a finite, auditable window, so
  an abandoned or stolen device eventually loses its session.

### Acceptance

1. ✅ `bin/magento config:show oauth/access_token_lifetime/customer` returns `720` (confirmed in admin 2026-08-26).
2. ⏳ Sign in on the app, leave it overnight, reopen: **still signed in**, and Account → My Orders loads.
   *This is the check that closes the ticket* — it needs real elapsed time, so it cannot be shortcut.
3. ⏳ A token issued *before* the change is still accepted after more than an hour (proves the retroactive behaviour).

---

## 3. Sign-outs that are *not* this bug

Document these so they don't come back as a re-report of CL042-DEV20 — all three are correct behaviour:

| Trigger | Effect | Why |
|---|---|---|
| Customer taps **Log Out** | `revokeCustomerToken` revokes **every** token for that customer | Magento's mutation is account-wide, not device-wide — logging out on the phone also signs out the tablet. |
| Customer **changes or resets their password** | All existing customer tokens are invalidated | Standard Magento security behaviour. |
| Customer **deletes their account** | Session ends | Expected. |

Anything else that signs a customer out is a bug worth reporting.

---

## 4. App side (already shipped — no backend action)

Both landed with this ticket; neither substitutes for §2.

- **Stopped a spurious logout at launch.** `StoreController._load()` runs on every cold start and used to wipe the
  customer token whenever the bootstrap `availableStores` call failed with the app's `service` failure kind. That
  bucket is *"the response wasn't JSON"* — which is usually an **AWS WAF / CloudFront error page** (CLAUDE.md §7),
  not a bad token. One transient edge hiccup therefore signed a perfectly valid customer out. The app now re-runs
  the query on a token-less client first and only clears the token if that guest call **succeeds** where the
  authenticated one failed. (Earlier related fix: `388805d`, same class of bug in `AuthController._restore`.)
- **Expiry is no longer silent.** When a session really is rejected, the app now shows a localized
  *"Your session has ended. Please sign in again."* (EN + AR) instead of a bare *"Something went wrong."*

---

## 5. Optional follow-up — `refreshCustomerToken` (sliding session)

A 30-day TTL still expires 30 days after *sign-in*, not after last use. A sliding session removes even that:
an actively-used app never ages out, while an abandoned device still dies on schedule.

**This is a spec only. The app does not call it and will not until it is deployed** — no dead code has shipped.

### SDL

```graphql
type Mutation {
    refreshCustomerToken: CustomerToken
        @resolver(class: "MagentoEgypt\PaymentGraphQl\Model\Resolver\RefreshCustomerToken")
        @doc(description: "Issue a fresh customer token for the authenticated customer, replacing the one that authorised this call.")
}
```

`CustomerToken` is Magento's existing core type (`{ token: String }`), so no new output type is needed.

### Resolver behaviour

1. **Require a live customer bearer.** If `$context->getExtensionAttributes()->getIsCustomer()` is false, throw a
   `GraphQlAuthorizationException` — an expired token must *not* be refreshable, or the TTL means nothing.
2. Mint a new token for that customer id (`Magento\Integration\Model\Oauth\TokenFactory` → `createCustomerToken($customerId)`),
   which is the same path `CustomerTokenService` uses.
3. **Delete only the presented token's row.** Do **not** call `revokeCustomerAccessToken($customerId)` — that is
   account-wide and would sign the customer out on all their other devices (see §3).
4. Return the new token.

### App-side hook point (when it exists)

`_ZoonzeAppState.didChangeAppLifecycleState` (`lib/app/app.dart`) already fires on `AppLifecycleState.resumed` and
refreshes the cart/wishlist there. The refresh call slots in beside them, gated on token age — which means
`SecureTokenStore` must also persist an issued-at timestamp next to the token, since a Magento token carries no
readable expiry. Suggested gate: refresh when the stored token is older than ~7 days.

### Acceptance

A customer bearer returns a **different, working** token; the old token stops working; a token belonging to a
*different* device for the same customer keeps working; and an expired bearer is refused.
