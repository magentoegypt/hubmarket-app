# Push Notifications — Magento Backend Contract

> **Status:** requirements / not yet implemented. Companion to [`payment-contract.md`](payment-contract.md).
> **App side:** the Flutter app already has the FCM plumbing (`lib/core/notifications/notification_service.dart`), a persisted **local inbox/feed** (`lib/features/notifications/`), a bell + unread badge in the chrome, and route mapping (`lib/app/notification_routes.dart`). What's missing is **(a)** a Firebase project, **(b)** a Magento endpoint to register device tokens, and **(c)** Magento sending FCM pushes on the events below.
>
> This document was drafted by parallel agents and **adversarially reviewed against the live app code** — the routing/payload rules here reflect what `notification_routes.dart` + `router.dart` actually do, not assumptions.

The three requested triggers — **new customer**, **reset password**, **new & update order** — all sit on top of two shared pieces: **device-token registration** (§2) and the **common payload contract** (§3). Read those first.

---

## 0. Scope & key facts (read first)

- Backend: Magento Open Source **2.4.8-p5**, GraphQL-first. Two store views: `uae-en` (en/LTR) · `uae-ar` (ar/RTL). New module mirrors `MagentoEgypt_PaymentGraphQl`.
- Transport: **Firebase Cloud Messaging (FCM) HTTP v1** only. The legacy server-key / `fcm.googleapis.com/fcm/send` endpoint is **deprecated — do not use**.
- The app records every push into a **local inbox** and shows a **bell badge**. The inbox dedups on **`data.message_id`** and categorises by **`data.type`**.
- **`type` drives the inbox icon; `route` drives the tap navigation — they are decoupled** (see §3). Get both right.
- Transactional pushes (order / welcome / reset / wishlist) are **token-targeted** to the customer's device(s). Only generic marketing uses the **`promotions` topic**.

---

## 1. Prerequisite — Firebase project (CLAUDE.md Open Question #9)

Nothing below works until a Firebase project exists and is wired both sides:

- **App side:** bundle `google-services.json` (Android) + `GoogleService-Info.plist` (iOS) per flavor (kept out of git). Until then FCM is disabled and `NotificationService.token()` returns null.
- **Server side:** a **Google service-account JSON** (scope `https://www.googleapis.com/auth/firebase.messaging`, role *Firebase Cloud Messaging API Admin*). Stored **outside the web root**, path injected via `env.php`/env var (mirror the `auth.json` hygiene rule); never committed. Project id read from the same config.
- Send endpoint: `POST https://fcm.googleapis.com/v1/projects/<PROJECT_ID>/messages:send`, `Authorization: Bearer <oauth2>` minted from the service account (cache the bearer until ~5 min before expiry).
- **Outbound egress** from the Magento origin to `fcm.googleapis.com` + `oauth2.googleapis.com` must be allowed (origin firewall/security-group — *not* a CloudFront/WAF change).

---

## 2. Device-token registration (foundation for all token-targeted pushes)

**Why it's required:** order/welcome/reset pushes are token-targeted, but the app currently has **no way to send its FCM token to Magento**. Add two GraphQL mutations + a token table.

### 2.1 GraphQL mutations (`schema.graphqls`)

```graphql
type Mutation {
  registerDeviceToken(input: DeviceTokenInput!): DeviceTokenResult!
    @resolver(class: "MagentoEgypt\\NotificationGraphQl\\Model\\Resolver\\RegisterDeviceToken")
    @doc(description: "Register/refresh an FCM token. Bearer present → bind to the customer; absent → store anonymously (customer_id NULL). Idempotent upsert keyed by token.")
  removeDeviceToken(token: String!): DeviceTokenResult!
    @resolver(class: "MagentoEgypt\\NotificationGraphQl\\Model\\Resolver\\RemoveDeviceToken")
    @doc(description: "Remove a device token (logout / permission revoked). Idempotent.")
}

input DeviceTokenInput {
  token: String!          # raw FCM registration token
  platform: String!       # "android" | "ios"
  app_version: String
}

type DeviceTokenResult { success: Boolean! }
```

- **Authorization / binding:** `registerDeviceToken` works **with or without** a bearer (guests need a token for the welcome push). With bearer → `customer_id` = authenticated customer; without → `customer_id` NULL. **Never** accept `customer_id` from the client — derive it from the bearer only.
- The resolver reads the **`Store` header** (already sent by the app) to set `store_id` → fixes the push locale per device.
- `removeDeviceToken` deletes only the row matching the token **and** (when a bearer is present) the authenticated customer.
- Both ride the **existing `/graphql` POST behavior** — no new CloudFront/WAF rule needed.

### 2.2 Token table — `magentoegypt_fcm_device_token` (`db_schema.xml`)

| Column | Type | Notes |
|---|---|---|
| `entity_id` | int PK auto-inc | |
| `token` | **varchar(512)**, **UNIQUE** | upsert key; FCM tokens can exceed 255 chars |
| `customer_id` | int NULL, FK→`customer_entity` ON DELETE CASCADE, indexed | NULL = guest/anonymous |
| `store_id` | smallint, FK→`store` | drives push locale (en/ar) |
| `platform` | varchar(16) | `android`/`ios` |
| `app_version` | varchar(32) NULL | diagnostics |
| `is_active` | bool default 1 | set 0 on dead-token signal |
| `fail_count` | smallint default 0 | soft-failure counter |
| `last_seen_at` | timestamp | bumped on every register call |
| `created_at` / `updated_at` | timestamp | |

### 2.3 When the app calls them (app-side dependency — see §8)

| Trigger | Call | Bearer |
|---|---|---|
| Token obtained / `onTokenRefresh` / **app launch heartbeat** | `registerDeviceToken` | if logged in |
| Login success | `registerDeviceToken` (re-bind guest token → customer) | yes |
| Store/language switch | `registerDeviceToken` (refresh `store_id`) | if logged in |
| Logout (before `revokeCustomerToken`) | `removeDeviceToken(token)` | yes |

### 2.4 Token lifecycle

- **Dedup** is structural (UNIQUE `token` + `INSERT … ON DUPLICATE KEY UPDATE`). A token moving between users just re-binds `customer_id`.
- **Per-customer cap** (default 10): evict oldest by `updated_at`.
- **Reactive prune:** on send, FCM HTTP v1 returning HTTP 404 `UNREGISTERED` (`messaging/registration-token-not-registered`) ⇒ delete the token. For HTTP 400 `INVALID_ARGUMENT`, **only** prune when the error `fieldViolations` cite the *token* field — otherwise it's a malformed-payload bug, alert don't delete. Transient `UNAVAILABLE`/`INTERNAL` ⇒ retry with backoff, never delete.
- **Proactive prune cron** (daily): delete rows with `last_seen_at` older than a TTL (≈270 d). ⚠️ **Depends on the app re-registering on launch** (§2.3 heartbeat) or live tokens get pruned — confirm with the app team.

---

## 3. Common FCM payload contract

Every message sends **both** a `notification{title,body}` block (OS banner when backgrounded) **and** a full `data` block (the app's inbox + routing; foreground `onMessage` only gets `data`). Mirror `title`/`body` into `data`. **All `data` values must be strings.**

```json
{
  "message": {
    "token": "<device_fcm_token>",
    "notification": { "title": "Order placed", "body": "Your order #000001234 has been placed." },
    "android": { "priority": "high", "notification": { "channel_id": "transactional" } },
    "apns": { "headers": { "apns-priority": "10" }, "payload": { "aps": { "sound": "default" } } },
    "data": {
      "type": "order",
      "message_id": "order_5512_placed",
      "title": "Order placed",
      "body": "Your order #000001234 has been placed.",
      "order_number": "000001234",
      "route": "/orders",
      "store": "uae-en"
    }
  }
}
```

### 3.1 `data` fields

| Field | Required | Values | Purpose |
|---|---|---|---|
| `type` | **Yes** | `order` · `delivered` · `promo` · `wishlist` · `welcome` · `general` | **Inbox icon/category.** Send the **exact** canonical value (don't rely on the app's keyword fallback). |
| `message_id` | **Yes** | stable, **deterministic per logical event** (no per-send timestamp) | **Dedup key.** Identical across every transport/retry of the same event. |
| `title` / `body` | **Yes** | localised | Mirror of the `notification` block. |
| `route` | see §3.2 | **path starting with `/`** | **Tap navigation.** |
| `order_number` | when order/delivered | `increment_id` string | Displayed in the inbox. *Not* used for routing (see §3.2). |
| `url_key` | when deep-linking a product | product `url_key` | Used by typed routing for `type:product` / explicit `/product/<url_key>`. |
| `store` | recommended | `uae-en` · `uae-ar` | Store view the copy was localised in. |

> **No secrets/PII ever.** No reset tokens, passwords, emails, phones, addresses, totals, or line items. `order_number` and `url_key` are the only permitted ids.

### 3.2 Routing rules — **verified against `lib/app/notification_routes.dart`**

`notificationRoute(data)` does, in order:
1. If `data.route` is a **string starting with `/`** → navigate there verbatim.
2. Else switch on `data.type`: `order`→`/orders` (list) · `product`+id→PDP · `category`+id · `cart` · `wishlist`→`/wishlist` · `promo`/`promotion`/`promotions`→`/home` · **anything else → no navigation**.

Consequences the backend **must** respect:

- **`welcome`, `delivered`, `general` have NO typed navigation** — they go nowhere unless you set an explicit **`route` (path form)**. Always include one (e.g. `/notifications`, `/orders`, `/home`).
- **`route` must be a path (`/…`), never a `zoonze://…` URI** — a custom-scheme value fails the `startsWith('/')` test and is ignored.
- **A specific order cannot be deep-linked today.** The `/order-detail` screen requires a `CustomerOrder` object in `state.extra` (`router.dart`), so a URL can't reach it; `type:order` lands on the **orders list** `/orders`. Send `type:order` + `order_number` and let the tap open `/orders`. *True order-detail deep-linking needs an app-side route change — see §8.*

### 3.3 Localisation

- Render `title`/`body` (and their `data` mirrors) in the **target device's store-view locale** (from the token's `store_id`), not the admin/creation locale. A customer with devices on different store views gets **one localised message per device** (resolve per token).
- Western numerals, **AED** (per resolved OQ#7). Never send a raw/unlocalised price.

### 3.4 Channels / priority (Android channels are fixed at creation)

| Class | `type` | `android.priority` | `channel_id` |
|---|---|---|---|
| Transactional | `order`,`delivered`,`welcome`,`wishlist`,`general` | `high` | `transactional` |
| Promotional | `promo` | `normal` | `promotions` |

### 3.5 Fan-out & dedup

- **HTTP v1 has no multicast** — fan out as a **loop of single-token sends** (the legacy `registration_ids` multicast is gone with the legacy API). Handle each token's error independently (§2.4).
- For one event sent to several of a customer's devices, keep **`message_id` identical** across tokens/locales — the app's inbox is **per-install**, so the same id is correct and collapses multi-transport duplicates per device.
- `message_id` scheme: **no per-send timestamp** for transactional events. Recommended: `order_<entity_id>_<transition>`, `welcome_<customer_id>`, `pwreset_<customer_id>_<request_ts>` (request time, stable for that request).

---

## 4. New customer (welcome) notification

| | |
|---|---|
| **Trigger** | `customer_register_success` observer (**verify it fires on the `createCustomerV2` GraphQL path on 2.4.8-p5** — see §9; if not, hook `customer_save_after` guarded by `isObjectNew()`, or plug `AccountManagementInterface::createAccount()`). Scope to the **frontend** area so admin-created customers don't trigger it. |
| **Targeting** | Token-targeted, transactional (never the promotions topic). |
| **Payload** | `type=welcome`, `route=/home` (or `/notifications`), `message_id=welcome_<customer_id>`. |
| en | **Welcome to Zoonze** — *Your account is ready. Start exploring fragrance, skincare & more.* |
| ar | **مرحباً بك في زونزي** — *حسابك جاهز. ابدأ باكتشاف العطور والعناية بالبشرة والمزيد.* |

**Token-timing (critical):** at `customer_register_success` the new customer often has **no token bound yet** (the app holds an anonymous guest token and re-binds it *after* registration). Therefore:
1. App registers its guest token **before** registration, then **re-binds** it to the new `customer_id` on success (§2.3).
2. **Don't send inline** — enqueue the welcome push (message queue) and **resolve the token set at consume time** (short delay, e.g. 30–60 s) so the re-bind lands first.
3. **Server-side idempotency is authoritative:** a `welcome_push_sent_at` claim flag per customer (atomic check-and-set) decides *whether* to send. `message_id` only collapses multi-transport duplicates of a single send — it does **not** prevent re-tries; the flag does.
4. **No token at consume time** → skip silently, mark `skipped_no_token`, rely on Magento's existing welcome **email**. Never re-open later.

---

## 5. Reset-password notification

A **notify-only heads-up**. The reset token/link travels **only** through the existing Magento email.

| | |
|---|---|
| **Trigger** | **Primary:** an `after`/`around` plugin on `Magento\Customer\Model\AccountManagement::initiatePasswordReset()` — it backs *both* `requestPasswordResetEmail` (GraphQL) and the web `ForgotPasswordPost`, so one hook covers all entry points. (A `customer_password_reset_request` **event** is *not* confirmed on 2.4.8-p5 — **verify before relying on it**, §9. Don't add two triggers or it double-fires.) |
| **Targeting** | Token-targeted to the customer's device(s). Unregistered email → observer never resolves a customer → **no push** (preserves enumeration safety). |
| **Payload** | `type=general`, `route=/notifications`, `message_id=pwreset_<customer_id>_<request_ts>`. **No** `order_number`/`url_key`. |
| en | **Password reset requested** — *We've emailed you a link to reset your password. If this wasn't you, you can ignore it.* |
| ar | **تم طلب إعادة تعيين كلمة المرور** — *أرسلنا إليك رابطًا عبر البريد لإعادة تعيين كلمة المرور. إذا لم تكن أنت، يمكنك تجاهل الرسالة.* |

**Hard security constraints (enforce in review):**
1. **Never** put the reset token, the reset URL (it embeds the token), the password, or any credential in `data`/`notification`.
2. The **only** channel that carries the reset link is the existing **email**. The push must not duplicate/replace it.
3. No PII in the payload (no email/name/phone). `message_id` uses the internal customer id, not the email.
4. **Tap target is inert** (`/notifications`) — never a screen that could action a reset.
5. **Enumeration-safe:** no push, and no distinguishable client signal, for a non-registered email. Inherits Magento's existing reset throttle (the hook fires only after Magento accepts the request).

---

## 6. New & update order notifications

Transactional, **token-targeted to the order's customer**, never topic-gated. Observers **enqueue only** (never call FCM inline — must not block `placeOrder`).

### 6.1 New order placed

| | |
|---|---|
| **Trigger** | `sales_order_place_after` (fires once, `increment_id` assigned; preferred over `checkout_submit_all_after`). |
| **Targeting** | `order.getCustomerId()` → device tokens. **Guest orders** (`customer_is_guest=1`): send only if a token was captured/associated at checkout, else **skip silently**. |
| **Payload** | `type=order`, `order_number=<increment_id>`, `route=/orders`, `message_id=order_<entity_id>_placed`. |
| en / ar | **Order placed** / **تم تقديم الطلب** — *Your order #000001234 has been placed.* |

### 6.2 Status / state updates

Use `sales_order_save_after` (guard on **status change**: `getOrigData('status') !== getStatus()`) for confirmation/cancel/hold, plus the specific entity-save events for richer messages. Each transition has a stable `message_id = order_<entity_id>_<transition>` so re-fires dedup client-side. **Skip** value-less transitions (e.g. `pending → pending_payment` during N-Genius/Tabby returns).

| Magento trigger | Condition | `type` | `message_id` | en title / body |
|---|---|---|---|---|
| `sales_order_save_after` | → `processing` | `order` | `order_<id>_processing` | **Order confirmed** — *Your order #N is being prepared.* |
| `sales_order_shipment_save_after` | shipment created | `order` | `order_<id>_shipped` | **Out for delivery** — *Your order #N is on its way.* |
| `sales_order_save_after` | state `complete` | `order` | `order_<id>_completed` | **Order completed** — *Your order #N is complete.* |
| `sales_order_save_after` | status `canceled` | `order` | `order_<id>_canceled` | **Order canceled** — *Your order #N has been canceled.* |
| `sales_order_creditmemo_save_after` | credit memo | `order` | `order_<id>_refunded` | **Order refunded** — *A refund was issued for order #N.* |

> ⚠️ **"Delivered" is not a native Magento status.** `complete` means *invoiced + shipped*, which is **not** actual delivery — do **not** label a `complete` push "delivered". Reserve **`type=delivered`** ("Order delivered — rate your experience", `route=/orders`) for a **real** delivery signal: a custom `delivered` order status or a carrier-tracking webhook. Until that exists, use `type=order` "completed" as above.

All order copy is localised from the **order's store view** (`order.getStoreId()`). Payload carries the order number only — the app re-queries order detail over authenticated GraphQL on open.

---

## 7. Module structure, ops & rollout

**Module:** `MagentoEgypt_NotificationGraphQl` (composer `magentoegypt/module-notification-graphql`), mirroring `MagentoEgypt_PaymentGraphQl`. Deps: `Magento_Customer`, `Magento_Sales`, `Magento_Store`, `Magento_GraphQl`, a message-queue module, and **`google/auth`** (+ Guzzle) for the v1 OAuth2 bearer — **not** the full firebase-admin SDK.

**Key pieces:**
- `Service/FcmSender` (POST to v1), `Service/AccessTokenProvider` (cached OAuth2 bearer), `Service/PushBuilder` (title/body/`data` + type/route + locale emulation), `Service/TokenTargetResolver`.
- `Observer/*` for each trigger (§4–6) — **publish to MQ topic `magentoegypt.fcm.send` only**, resolve tokens at consume time, never send inline.
- `Queue/FcmSendConsumer` — resolve tokens → build → loop single-token sends → retry/prune.
- `Cron/PruneDeadTokens` (+ optional retry sweeper).
- `etc/adminhtml/system.xml` — Firebase credential path + project id, **per-event enable flags (all default OFF)**, retry/prune settings; ACL-gated.
- `i18n/en_US.csv` + `i18n/ar_SA.csv` for strings (optional admin template override per event, store-view scoped, whitelisted placeholders `{order_number}`/`{customer_firstname}` only).
- Logging → `var/log/magentoegypt_fcm.log`; **never log full tokens** (hash/last-6) or PII; counters for sent/failed/pruned.

**Rollout (ordered, gated):**
1. Firebase project (OQ#9).
2. Service account JSON on server (out of web root) → admin config.
3. Bundle Firebase config files in the app; verify `NotificationService.token()` returns a token.
4. Deploy module **with all events OFF**; confirm `registerDeviceToken`/`removeDeviceToken` work (rows land in the table).
5. CLI/admin "send test push" → confirm the device shows it and the inbox categorises by `type` + dedups by `message_id`.
6. Enable events one at a time: **welcome → order_placed → shipment/completed → password_reset**; verify locale + tap routing each step.
7. Enable prune cron; review logs/counters.

---

## 8. App-side dependencies (changes the app needs)

These are **not** backend work but block end-to-end delivery — track alongside:

1. **Bundle Firebase config** (`google-services.json` / `GoogleService-Info.plist`) so FCM activates.
2. **Call the token mutations:** `registerDeviceToken` on app launch + `onTokenRefresh` + login + store switch; `removeDeviceToken` on logout. (The service exposes `NotificationService.token()`; the wiring is TODO.)
3. **Guest-token pre-register + re-bind** around registration (enables the welcome push, §4).
4. **Order-detail deep link (optional enhancement):** add a route like `/orders/<increment_id>` that fetches the order by increment id, so order pushes can land on the specific order instead of the list (§3.2). Until then, backend sends `route=/orders`.
5. **`promotions` topic opt-in** already exists (`kPromoTopic`); promo blasts use it. Wishlist/price-drop pushes are **token-targeted only — never the shared topic** (or every subscriber sees another user's price drop).

---

## 9. Verify on 2.4.8-p5 before implementing

- [ ] Does `createCustomerV2` (GraphQL) actually dispatch **`customer_register_success`**? If not, use the `customer_save_after`/`createAccount`-plugin fallback (§4).
- [ ] Is there a dispatched **password-reset event**, or must we plug `AccountManagement::initiatePasswordReset()`? (§5 assumes the plugin.)
- [ ] Confirm the **guest-order → device-token** association path at checkout (for guest order pushes, §6.1).
- [ ] Decide one Firebase project across flavors vs per-flavor.
- [ ] Confirm the app adds a **launch heartbeat** `registerDeviceToken` (else the 270-day prune kills live tokens, §2.4).
