# WhatsApp OTP contract — `MagentoEgypt_OtpVerification`

The live module that adds WhatsApp one-time passcodes to auth + guest checkout.
Verified against `https://zoonze.com/graphql` (`Store: eg_en`) on 2026-07-08. This
is the app-facing distillation; the full backend brief is the source of truth.

The app consumes the **GraphQL** surface (GraphQL-first). All OTP mutations are
**anonymous**; `loginWithOtp` returns a customer token to use as
`Authorization: Bearer …` thereafter.

## Mutations (confirmed on the live schema)

```graphql
requestRegistrationOtp(phone: String!): OtpResult
verifyRegistrationOtp(phone: String!, code: String!): OtpResult
requestLoginOtp(phone: String!): OtpResult
loginWithOtp(phone: String!, code: String!): OtpLoginResult
requestPasswordResetOtp(phone: String!): OtpResult
resetPasswordWithOtp(phone: String!, code: String!, newPassword: String!): OtpResult
requestGuestCheckoutOtp(cartId: String!): OtpResult      # cart-bound (no phone arg)
verifyGuestCheckoutOtp(cartId: String!, code: String!): OtpResult

type OtpResult      { success: Boolean!  message: String }
type OtpLoginResult { success: Boolean!  token: String  message: String }
```

- **Failure = a GraphQL `errors[]` entry** with an already-localized (eg_en/eg_ar)
  message — *not* `success:false`. The app maps that to `Failure(server, detail:)`
  and surfaces `detail` verbatim (see `serverMessageOr`, `lib/core/widgets/failure_message.dart`).
- `requestLoginOtp` / `requestPasswordResetOtp` **always** return `success:true`
  (anti-enumeration) — never infer account existence from them.

## Phone format

Send **E.164** (`+971501234567`). A bare local `05x…` is accepted (server
normalizes with default country +971), but the app always sends the explicit
`+971…` form via `Phone.normalizeUae` (`lib/core/validation/phone.dart`). The
value stored in the `mobile_number` custom attribute at registration **must equal
the verified number**. UAE mobile shape: `+9715[0/2/4/5/6/8]XXXXXXX`.

## Flows (as wired in the app)

| Flow | Screen | Calls |
|---|---|---|
| Passwordless login | Sign In · Phone tab | `requestLoginOtp` → `loginWithOtp` → token |
| Registration | Sign Up (inline mobile) | `requestRegistrationOtp` → `verifyRegistrationOtp` → `createCustomerV2(custom_attributes:[{mobile_number}])` → login |
| Forgot password | Forgot · Phone tab | `requestPasswordResetOtp` → `resetPasswordWithOtp` → sign in |
| Guest checkout | Checkout · Guest Verify card | set shipping address (with `+971…` telephone) → `requestGuestCheckoutOtp` → `verifyGuestCheckoutOtp` → `placeOrder` |

- **Registration guard** requires a verified `mobile_number`; it covers both REST
  `POST /V1/customers` and GraphQL `createCustomerV2`. `CustomerCreateInput.custom_attributes`
  is confirmed on the live schema. Fallback if GraphQL ever drops it: REST create
  (`POST /rest/eg_en/V1/customers`).
- **Guest-checkout guard** blocks `placeOrder` (both GraphQL and REST) until a
  verified OTP is bound to the quote. The app gates the Place Order button on
  `guestOtpVerified` for a clean UX instead of hitting the raw guard error.

## Throttle limits (surface in UI)

6-digit code · TTL **300s** · resend cooldown **60s** (see `ResendCountdown`) ·
max **5** verify attempts · max **5** sends/hour/phone · post-verify window **900s**
(registration must create the account within it).

> ⚠️ WhatsApp is **live** — every request sends a real message. Test with a real
> UAE number you control; automated tests mock the GraphQL client.
