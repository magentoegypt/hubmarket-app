# App Review Information — Notes field

Paste-ready text for the **Notes** box in App Store Connect (4,000 char limit).
Fill in the two bracketed values before pasting.

Everything below is true of the shipped build and was checked against the code
or verified on device. Don't add claims a reviewer can't reproduce — a note
that promises something the app doesn't do is worse than no note.

---

```
ABOUT

Zoonze is the shopping app for zoonze.com, a beauty and fragrance retailer in
the United Arab Emirates. The app is a client of our existing storefront —
catalog, pricing, cart and orders all come from our live backend.

ACCOUNT DELETION (Guideline 5.1.1(v))

Build 1.0.0 (80) was rejected for this. The option existed but was reachable
only through a row labelled "Language", so it could not reasonably be found. In
this build it is on the main Account screen.

To reach it:

1. Sign in with the demo account in the Sign-In Information fields above.
2. Tap the Account tab (bottom right).
3. Scroll down. "Delete account" sits between "About Zoonze" and "Log Out".
4. Tap it. A dialog states what is removed; confirm with "Delete account".

The account is then permanently deleted from our systems and the app returns to
a signed-out state. It is a deletion, not a deactivation, and needs no website
visit, phone call or email. A screen recording of this flow, captured on a
physical device, is attached to our reply.

Saved addresses and wishlist are erased. Order and invoice records are retained
for the period UAE tax and consumer law requires — the confirmation dialog says
so rather than overstating what is removed.

The deletion is real. If you delete the demo account while testing, tell us and
we will recreate it.

PHYSICAL GOODS ONLY — NOT IN-APP PURCHASE

Every item sold is a physical product (fragrance, skincare, makeup, hair care)
shipped to a street address in the UAE. Per Guideline 3.1.5(a), physical goods
and services are purchased outside of in-app purchase. The app sells no digital
content, subscriptions, or unlockable functionality.

SIGN-IN

A demo account is provided in the Sign-In Information fields above.

Signing in is not required to review most of the app: tap "Continue as guest"
on the welcome screen to browse the full catalog, search, and add items to a
cart. An account is needed only to place an order and to view order history.

HOW TO TEST A PURCHASE WITHOUT PAYING

At the payment step, choose Cash on Delivery. This places a real order in our
system with no card details and nothing charged. Please use the demo account so
we can identify and cancel the test order. Order confirmation, order history
and order tracking all work from this path.

LANGUAGES — ENGLISH AND ARABIC

Both are fully supported. Switch using the EN / AR toggle at the top of the
welcome screen, or later under Account > Language. Arabic renders the entire
interface right-to-left, and product and category names are served in Arabic
from our backend.

REGION

The store serves the UAE. Prices are shown in AED and delivery addresses are
limited to the seven emirates. The app itself is usable from any region — only
shipping is restricted — so everything is reviewable from outside the UAE.

PUSH NOTIFICATIONS

Used only for order status updates. iOS asks for permission on first launch;
the app is fully functional if permission is declined.

CONTACT

[YOUR NAME / EMAIL] — happy to provide anything else needed for review.
```

---

## Account deletion — resolved in 1.0.0 (build 76)

**Guideline 5.1.1(v):** an app that lets users create an account must let them
**delete** that account from within the app. Deactivation is not sufficient,
and pointing the user at a website or a support email is not sufficient.

Zoonze creates accounts (`createCustomerV2`, Sign Up screen), so the rule
applies. Builds up to and including **75** shipped only
`deleteCustomerAddress` and `deleteCustomerAvatar` — nothing that deleted the
account itself — and would have failed review on this alone.

**Build 82:** a destructive "Delete Account" action on the Account screen, shown
only when signed in. It confirms first, calls Magento's `deleteCustomer`, then
clears the token and cart and returns to the signed-out state. A server-side
failure leaves the customer signed in rather than faking success.

**Do not submit build 81 or earlier.** The build attached to the App Store
version must be 82 or later. 1.0.0 (80) was rejected under this guideline
because the action existed only behind a row labelled "Language" — see
rejection-5.1.1v-account-deletion.md.
