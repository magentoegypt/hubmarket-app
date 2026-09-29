# Huawei AppGallery — submission pack

Companion to the App Store material in this folder. Most of the content
transfers: [`listing-en.md`](listing-en.md) and [`listing-ar.md`](listing-ar.md)
carry the description and promo copy, [`app-privacy.md`](app-privacy.md) the
data-collection answers, [`review-notes.md`](review-notes.md) the reviewer
instructions and demo-account rationale. This file covers only what is
**different about AppGallery**.

Automation: [`.github/workflows/release-huawei.yml`](../../.github/workflows/release-huawei.yml).

---

## 0. Before anything else — the account

Nobody can do this part for you: it needs company documents and a person
accepting terms. Verified against Huawei's own docs on 2026-09-27 (those pages
were last updated 2026-04-22).

### 0.1 HUAWEI ID

Register at **developer.huawei.com** → *Sign in* → register with an email
address or mobile number, verify the code, set a password, accept the Privacy
Notice and Terms.

Use a **company mailbox you will still control in two years**, not a personal
one — the account owns the app listing, and moving it later is painful.

### 0.2 Enterprise identity verification

Console → *Identity verification* → select **Enterprise** (not Individual —
individual accounts cannot publish under a company name, and switching means
re-verifying).

Two routes; you only need one:

| Route | What it needs |
| --- | --- |
| **DUNS number** | An **active** DUNS, renewed within the last 2 years. Look it up on the official DUNS site by company name + address, or apply for one free |
| **Business license** | Click **"I don't have a DUNS number"**. A trade/business licence showing company name, registration number, tax number and registration date — a UAE trade licence qualifies |

**The single most common rejection is a name mismatch.** *Legal entity name*
and *Legal entity name (English)* must match the DUNS or licence **exactly** —
letter case, punctuation and spacing included. Copy and paste; do not retype.

Most countries also require the **contact person's** documents:

- **Identity:** national ID, passport, or another official document (e.g.
  driving licence) — a scan showing the full name **in English** and a clear
  photo, issued by the authorities of the country you select.
- **Bank document:** bank card, bankbook, account-opening confirmation, or a
  statement — showing the same full name in English, and **valid for at least
  6 months**.

**Review takes 1–2 working days**, with the result emailed to the contact
address and shown as a banner in the console.

### 0.3 App record and API client

Once verified:

1. **AppGallery Connect → My apps → New app**: package name **`com.zoonze.shop`**
   (must match the built artifact exactly), app name, default language,
   category *Shopping*.
2. Note the numeric **App ID** from *App information* — that is
   `HUAWEI_AGC_APP_ID`, **not** the package name.
3. **AGC → Users and permissions → API client**, with the Connect API role.
   It issues a **client ID** and a **client secret**; the secret is shown
   **once**. They become `HUAWEI_AGC_CLIENT_ID` / `HUAWEI_AGC_CLIENT_SECRET`.

> Whoever owns this account owns the listing. If it should belong to the
> client rather than the agency, create it under their company and their
> documents from the start — this is not cheap to undo.

## 1. Signing — shared with Google Play

AppGallery rejects a debug-signed artifact exactly as Play does, and the repo
falls back to the debug key whenever `android/key.properties` is missing.

The upload keystore already exists (see the Android signing note: alias
`zoonze`, RSA 2048, valid to 2053). It needs to reach CI as four secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 zoonze-release.jks` |
| `ANDROID_STORE_PASSWORD` | keystore password |
| `ANDROID_KEY_PASSWORD` | key password |
| `ANDROID_KEY_ALIAS` | `zoonze` |

**These are the same four the Play lane reads**, so adding them once unblocks
both stores. Unlike Play, AppGallery has no re-signing service: the key you
sign with here is the key you must keep forever. Losing it means never
updating the app.

## 2. What is different on Huawei devices

**No Google Play Services.** Huawei phones released from 2019 ship without GMS.
Checked against this codebase:

- `Firebase.initializeApp` is wrapped in try/catch and degrades to
  "FCM disabled" — the app **starts and runs normally** on a GMS-less device.
  This was the dead-on-arrival risk and it does not apply.
- **Push will not work** on those devices. It does not work anywhere yet
  (backend blocker #4), so AppGallery is not a regression — but when push does
  land, Huawei users need **HMS Push Kit** as a second path, not just FCM. Plan
  that as its own piece of work.
- No other GMS-dependent dependency is in `pubspec.yaml`: the only Google
  packages are `firebase_core` and `firebase_messaging`.

**Samsung Pay** is offered by the backend but its SDK is Samsung-only; the
app's device-capability probe already filters it, so it simply will not appear
on Huawei hardware.

**Do not claim push in the listing** until HMS Push Kit is integrated —
advertising a feature the reviewer can test and find missing is a rejection.

## 3. Listing

Reuse `listing-en.md` and `listing-ar.md`. AppGallery differs from Apple in:

| Field | Note |
| --- | --- |
| Description | 8000 chars (Apple: 4000) — the existing copy fits with room to spare |
| Brief introduction | ~80 chars; adapt the App Store **subtitle** |
| Keywords | Provided as a list, not a comma-joined string |
| Screenshots | Minimum 3, portrait, JPG/PNG. Apple's can be reused if they carry no Apple-specific chrome |
| App icon | 216×216 PNG |
| Privacy policy URL | **Required** — same URL as the App Store submission |
| Age rating | Huawei's own questionnaire; answer as for Apple's 4+ |
| Languages | Publish **English and Arabic** — the app is bilingual and the listing already exists in both |

## 4. Review

Huawei's reviewers test the app like Apple's, so the same preparation applies:

- Give them the **demo account** — see `review-notes.md`. The app gates
  checkout behind sign-in, and a reviewer without credentials fails it.
- Reuse the reviewer notes from `review-notes.md`, including the account
  deletion explanation (Huawei asks about deletion too) and the note that
  payments run in a sandbox with nothing charged.
- Expect a question about **why push is absent**, given the app requests
  notification permission. Answer plainly: the feature is not yet enabled
  server-side.

## 5. Running the workflow

`Actions → Release · Huawei AppGallery → Run workflow`.

- `format: apk` is the safer first choice — widest device support and it is
  directly installable for sanity-checking. `aab` gives a smaller download.
- `submit: false` (the default) uploads the build and binds it to the app
  record as a **draft**. Somebody then presses submit in the console. Use
  `true` only when you mean to enter Huawei's review queue.

> ⚠ **The AGC Publishing API calls in that workflow have never been executed.**
> They are written from Huawei's documented v2 sequence (token → upload-url →
> upload → app-file-info → app-submit) against no real app record. The first
> run should be treated as a dry run: it uploads the artifact to the GitHub run
> as well, so a failed API call never costs a rebuild, and each step prints the
> raw response so a wrong field name is visible rather than silent. Expect to
> correct at least one thing.

## 6. Order of operations

1. Enterprise account verified (days — start now).
2. App record created, App ID noted.
3. API client created, ID + secret captured.
4. Six secrets added in GitHub: four `ANDROID_*`, two `HUAWEI_AGC_*`, plus
   `HUAWEI_AGC_APP_ID`.
5. Run the workflow with `submit: false`; confirm the build appears in AGC.
6. Fill the listing, upload screenshots, answer the age rating, attach the
   demo account.
7. Submit from the console.
