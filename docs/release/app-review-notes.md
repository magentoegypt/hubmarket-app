# App review notes: Apple's Notes box and Google Play's App access

Paste-ready text for the **Notes** field of *App Review Information* in App Store Connect (4,000
characters) and for *App access* in Google Play Console. Fill in the bracketed values first; each
line is true of the shipped build or marked as a client input. Do not add a claim a reviewer cannot
reproduce: a note that promises something the app does not do is worse than no note.

## What the client must prepare

| Item | Why |
|---|---|
| A **demo account** on the server the release build talks to (email and password) with at least one past order | Apple asks for sign-in details when the app has accounts; Play asks for them under App access. Order history, returns, credit and account deletion need an account. Create it by hand in the store admin: nobody but the client should hold real credentials. |
| A **screen recording on a physical device** of the deletion flow, made with a throw-away account | Apple asked Zoonze for exactly this after a 5.1.1(v) rejection. Deletion is permanent, so never record with the demo account. |
| A named **contact** (name, email, phone) for the review team | Field on both stores. |
| A note on **test orders**: who cancels the reviewer's cash-on-delivery orders | The reviewer will place a real order in the live system. |

## App Store Connect: Notes

```
ABOUT

Hub Market is the shopping app for a multi-vendor marketplace in the United Arab Emirates. It is a
client of our existing web store: the catalogue, prices, carts and orders all come from our live
backend. Each product is sold and shipped by an independent store (seller) shown on its page.

SIGN-IN

A demo account is in the Sign-In Information fields above. Signing in is not needed to review most
of the app: tap "Continue as guest" on the welcome screen to browse the whole catalogue, search,
open stores and add items to the cart. An account is needed to see order history, start a return,
use store credit and manage addresses. The app has no third-party or social sign-in (only e-mail
and password, or a one-time code sent by WhatsApp), so Sign in with Apple does not apply.

ACCOUNT DELETION (Guideline 5.1.1(v))

1. Sign in with the demo account.
2. Open the Account tab (bottom right).
3. Tap "Privacy & data" (the row ends with the words "Delete account").
4. Tap "Delete my account", tick "I understand this can't be undone" and confirm.

The account is permanently deleted through our backend and the app returns to a signed-out state.
It is a deletion, not a deactivation, and needs no website visit or e-mail. Order and invoice
records are kept for the period UAE law requires; the screen says so. The same action is also in
Account > Settings. A screen recording of the flow on a physical device is attached to our reply.
The deletion is real: if you delete the demo account while testing, tell us and we will recreate it.

PHYSICAL GOODS ONLY, NOT IN-APP PURCHASE

Everything sold is a physical product delivered to an address. Under Guideline 3.1.3(e) (goods and
services outside of the app) payment is not made through in-app purchase. The app sells no digital
content, subscriptions or unlockable features. Store credit exists only to pay for these physical
goods in the same store; it does not unlock anything in the app.

HOW TO TEST A PURCHASE WITHOUT PAYING

At the payment step choose Cash on Delivery. This places a real order in our system with no card
details and nothing charged. Please use the demo account so we can identify and cancel the test
order. Order confirmation, order history, tracking and returns all work from this path. A return
can be started from an order that is processing or complete.

USER-GENERATED CONTENT (Guideline 1.2)

Customers can write product reviews. Every review is held for approval by our staff before it is
shown ("Your review is awaiting approval"). Customers can contact us from Account > Help centre,
which has a contact form and a WhatsApp link.

LANGUAGES

English and Arabic. Switch on the welcome screen or in Account > Settings > Language. Arabic
mirrors the whole interface right to left, and product, category and store names come from our
backend in Arabic.

REGION

The store serves the UAE and prices are in AED. The app itself opens from any region, so every
screen can be reviewed from outside the UAE.

PUSH NOTIFICATIONS

[Only if Firebase is live in this build:] Used only for order updates. iOS asks for permission on
first launch; the app is fully usable if it is declined and the customer can switch them off in
Account > Notifications.
[Otherwise delete this section: this build sends none.]

PRIVACY

No advertising, no tracking, no analytics SDK. The privacy policy is at [URL]. Photos are only
used when a customer attaches them to a return request; the app never asks for library access.

CONTACT

[NAME, E-MAIL, PHONE]: glad to provide anything else needed for review.
```

It is about 3,600 characters of the 4,000 allowed. Delete the Push section if it does not apply.

## Google Play Console: App access

Choose *All or some functionality is restricted*, add one instruction set:

```
Name: Reviewer account
Username: [demo e-mail]
Password: [demo password]
Instructions: Most of the app opens without signing in: tap "Continue as guest", then browse,
search, open a store and add to the cart. Sign in with the account above to see order history,
returns, store credit and Account > Privacy & data (delete account). Payment is cash on delivery;
choose it at checkout, using this account so we can cancel the test order.
```

Other App content declarations (details in [privacy-and-data-safety.md](privacy-and-data-safety.md)):
ads: none; target audience: 18 and over; content rating: complete the questionnaire as Shopping
with user-generated content (reviews); Data safety: sections 4 and 6 of the privacy document.

## Before each submission

- The build attached to the version is the one the notes describe, and the deletion path in the
  notes is the path in that build.
- The demo account still exists and can sign in on the server the build talks to.
- Screenshots and listing text match the build (see [store-listing.md](store-listing.md)).
