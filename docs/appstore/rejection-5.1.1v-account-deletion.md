# Rejection: Guideline 5.1.1(v) — account deletion

**Submission** 28fb6291-3ce3-4ae0-a7c1-d3a12897ccf1 · reviewed 2026-08-13 on
iPhone 17 Pro Max · version reviewed **1.0.0 (80)**.

> The app supports account creation but does not include an option to initiate
> account deletion.

## What actually happened

The option was there. It shipped in **1.0.0 (76)** and was in build 80. The
reviewer could not find it, and neither would a customer:

    Account → "Language"  (globe icon, showing "English") → Settings → Delete Account

The only route into Settings was a row labelled **Language**. Nobody hunting for
account deletion taps that, so in practice the feature did not exist.

The guideline is about the option being **findable**, not merely present, so
this was a fair rejection rather than a reviewer miss.

## Fix — 1.0.0 (82)

**Delete Account** now sits directly on the Account screen, immediately above
Log Out, alongside Edit Profile / My Orders / My Wishlist / Saved Addresses. It
remains in Settings as well, and both share one implementation
(`confirmAndDeleteAccount`) so the confirmation, the mutation and the local wipe
cannot drift apart.

Path a reviewer will follow:

    Account tab → Delete Account → confirm → account deleted, returned signed-out

Behaviour is unchanged from 76: confirmation dialog naming what is lost (saved
addresses, wishlist, order history), then Magento's `deleteCustomer`, then the
token and cart are cleared and the app drops to guest. A server-side failure
leaves the customer signed in rather than faking success.

## Before resubmitting

**Attach build 82 or later.** Builds ≤ 80 have the option only behind
"Language", which is what was rejected.

**Record the demo Apple asked for** — on a physical device, showing:

1. Signing in with the demo account (or creating an account)
2. Navigating to the deletion option — Account tab, Delete Account
3. The whole flow through to confirmation

Apple asked for this recording in the reply *and* in the App Review Information
**Notes** field for future submissions.

Note the deletion is real and permanent: record it with a throwaway account, not
the demo account the reviewer needs, and recreate the demo account afterwards.

## Reply to send in App Store Connect

> Thank you for the review.
>
> Account deletion is available in the app. In the version you reviewed it was
> reachable only through Account → Language → Settings → Delete Account, which
> we agree is not discoverable — the entry point was labelled "Language", so
> there was no reasonable way to find it.
>
> In build 82 we have moved **Delete Account** onto the main Account screen,
> directly above Log Out, so it is visible as soon as a signed-in customer opens
> the Account tab. It also remains in Settings.
>
> To reproduce: sign in with the demo account in App Review Information, open
> the **Account** tab, and tap **Delete Account**. A confirmation dialog states
> what will be removed (saved addresses, wishlist and order history); confirming
> permanently deletes the customer record from our systems and returns the app
> to a signed-out state. It is a deletion, not a deactivation, and needs no
> customer-service contact or website visit.
>
> A screen recording of the full flow on a physical device is attached.
>
> Please note the deletion is permanent, so if you delete the demo account
> during testing, let us know and we will recreate it.

## Related

- `docs/appstore/review-notes.md` — the ACCOUNT DELETION section already
  describes the flow; update the path from "Account > Settings > Delete Account"
  to "Account > Delete Account" before resubmitting.
