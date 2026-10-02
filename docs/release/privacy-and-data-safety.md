# Privacy and data safety: what the app collects, and the answers for both stores

Answers for **Apple's App Privacy** section and **Google Play's Data safety** form, written from
the code (main at 30 Sep 2026) and from what the backend exposes, not from assumption. Each
"yes" says what collects it. Both forms are legal declarations that the stores check against the
app's behaviour, so where a call was a judgement rather than a fact it is marked **CONFIRM**.
Over-declaring is not penalised; under-declaring is.

**Keep three things in step:** this document, `ios/Runner/PrivacyInfo.xcprivacy`, and the two store
forms. Re-check all three when a payment gateway, Firebase, analytics or crash reporting is added.

**The short version.** The app collects what a shop needs to take and deliver an order: contact
details, delivery addresses, orders, returns (with optional photos), reviews and messages, a
customer id, and (once push is on) a push token. It sends search terms to the store's search. It
does **not** track people, show ads, read location, contacts or the advertising id, or bundle an
analytics or crash-reporting SDK. Payment is cash on delivery, so it never handles card details.

---

## 1. What the app does with personal data

| Data | Where it enters the app | Goes to | Why |
|---|---|---|---|
| Name, email, phone, password | Register, sign in (email and password, or a WhatsApp code), profile | The Hub Market store (Magento), over HTTPS | Account and sign-in. The password is only sent to sign in, create the account or change it; it is never kept on the phone. |
| Delivery addresses (name, street, city, region, postcode, country, phone) | Checkout, address book | The store. **The seller of each item receives the delivery details** to ship it. | Delivery |
| Guest checkout details | Checkout without an account | The store, then the seller as above | Delivery, order confirmation |
| Orders, returns, store credit, reviews, wishlist | Ordering, "Return items", "My credit", writing a review | The store; a return is visible to the seller and the store's staff | Order service |
| Photos on a return request and its replies | Chosen or taken by the customer through the system picker or camera; the app never asks for library or storage access. Resized to at most 2048 px and re-encoded. | The store; visible to the seller and staff | Showing the seller what is wrong |
| Contact form message (name, email, message) | Help centre | The store's own contact form; the message is e-mailed to the store | Customer support |
| Search terms | Search box | **Algolia** (the store's search provider). The searches are tagged `app` for the store's Algolia Analytics (only the extra filter-count queries switch analytics off) and no user token is sent, so Algolia counts users by connection address. If Algolia cannot be reached, the store's own search answers. | Search results |
| Push token, platform, app version, language | Only when Firebase is configured and the customer has not turned notifications off | The store, bound to the customer's account (or kept as a guest device) | Order updates. Removed at sign-out or when notifications are switched off. |
| Sign-in token | After sign-in | Stored on the phone in the platform's secure storage (Keychain, Android Keystore-backed) | Staying signed in |
| Language and store view, recent searches, guest cart id, a short list of guest orders (order number, lookup token, and the billing email and last name used to re-open them), cached store data | Use of the app | **Stays on the phone** (local storage). The sign-in token and the cart are cleared at sign-out or account deletion; the rest goes when the app is uninstalled. | Convenience |

**Not collected:** location, contacts, calendar, microphone, the advertising id, browsing history
outside the app, health data, payment card details, analytics or crash data. There is no tracking
and no third-party advertising, so the app needs no App Tracking Transparency prompt and no
consent banner.

## 2. Who else receives data

| Party | Role | What they get | To do |
|---|---|---|---|
| Hub Market store (the client's Magento server) | Controller of the customer data | Everything in section 1 | Name the legal entity in the privacy policy. |
| Marketplace sellers | Independent parties fulfilling their own orders | Name, phone, delivery address and the order for their own items; return messages and photos | Confirm which fields the seller panel shows (Vnecoms), and say so in the policy. |
| Algolia | Service provider (search and search analytics) | Search terms, and the connection's IP address | The client signs Algolia's data-processing agreement and names its hosting region and analytics retention in the policy. |
| Google Firebase Cloud Messaging | Service provider (push), **only once Firebase is set up** | Push token, installation id | Follow Google's "Data safety" and Apple's privacy-details pages for Firebase when it goes live. |
| WhatsApp or SMS code delivery (SmsExtend on the server) | Service provider | The phone number and the code | Name the provider in the policy. |
| Apple and Google | Distribution, push delivery | Their own account data | – |

No data is sold. No data goes to a data broker or is joined with third-party data for ads.

## 3. Apple: App Privacy answers

Tracking: **No** for every type. Purpose for every type below: **App Functionality** only. The
same list is in `ios/Runner/PrivacyInfo.xcprivacy`.

| Apple category | Collected | Linked to the user | What collects it |
|---|---|---|---|
| Contact info: Name | Yes | Yes | Register, addresses, checkout, contact form |
| Contact info: Email address | Yes | Yes | Register, sign-in, guest checkout, contact form |
| Contact info: Phone number | Yes | Yes | Profile, WhatsApp code sign-in, addresses |
| Contact info: Physical address | Yes | Yes | Address book, checkout |
| Purchases: Purchase history | Yes | Yes | Orders, returns, store credit |
| User content: Photos or videos | Yes | Yes | Return photos (optional) |
| User content: Customer support | Yes | Yes | Help centre contact form |
| User content: Other user content | Yes | Yes | Reviews |
| Identifiers: User ID | Yes | Yes | The customer account behind the sign-in token |
| Identifiers: Device ID | Yes, **once push is on** | Yes | FCM push token |
| Search history | Yes (**CONFIRM**) | No | Search terms reach Algolia (with its analytics, which counts users by connection address) and the store's search (which keeps terms and counts for its own reporting); no customer id is sent with them. A stricter reading would call the connection address a link: if the client prefers it, declare "linked". |
| Financial info (payment info, other) | **No** | – | Cash on delivery: no card data. **CONFIRM** if the store credit balance should also be declared as "Other financial info"; we treat it as purchase history. |
| Location, Contacts, Health, Sensitive info, Browsing history, Usage data, Diagnostics | No | – | Nothing collects them |

**Also on the version page:** "Does this app use the Advertising Identifier (IDFA)?" **No**; export
compliance is already answered in the app (`ITSAppUsesNonExemptEncryption` false).

**Privacy policy URL** is required and blocks publishing the section: it must be a live page that
describes what is above (see section 8).

## 4. Google Play: Data safety answers

**Does the app collect or share data?** Yes. **Is all of it encrypted in transit?** Yes (HTTPS
only). **Can people ask for their data to be deleted?** Yes: in the app, and through a web page
(section 7). **Committed to the Play Families policy?** No: the app is not for children.

| Play data type | Collected | Shared | Required or optional | Purposes |
|---|---|---|---|---|
| Personal info: Name | Yes | Yes, with the seller of the ordered items | Required to order | App functionality, account management |
| Personal info: Email address | Yes | Yes (**CONFIRM** what the seller panel shows) | Required to order | App functionality, account management |
| Personal info: Phone number | Yes | Yes, with the seller | Required to order | App functionality, account management |
| Personal info: Address | Yes | Yes, with the seller | Required to order | App functionality |
| Personal info: User IDs | Yes | No | Required for an account | Account management |
| Financial info: Purchase history | Yes | Yes, each seller sees its own orders | Required to order | App functionality |
| Financial info: User payment info | **No** | – | – | Cash on delivery. **Revisit** when card, Tabby or Tamara arrive. |
| Photos and videos: Photos | Yes | Yes, with the seller of the returned item | Optional | App functionality |
| Messages: Other in-app messages | Yes (return replies, contact form) | Yes, return replies go to the seller | Optional | App functionality, customer support |
| App activity: In-app search history | Yes | No: Algolia processes it for the store | Required to search | App functionality |
| App activity: Other user-generated content | Yes (reviews) | Reviews are shown publicly on the store | Optional | App functionality |
| Device or other IDs | Yes, **once push is on** (FCM token) | No | Optional (notifications can be switched off) | App functionality |
| Location, Contacts, Audio, Files, Calendar, Health | No | – | – | – |
| App info and performance: crash logs, diagnostics | **No**, no such SDK is bundled | – | – | – |

**Shared with a seller.** Play lets a developer leave out a transfer the user starts knowingly
(placing an order is one). The safe reading, used above, is to declare the delivery details as
shared with sellers; the client's counsel can decide to narrow it.

**Data deletion.** State that orders and invoices are kept as long as UAE law requires; the
in-app dialog says the same.

## 5. Permissions and system prompts

**Android** (merged manifest of the dev build, read with `aapt2 dump permissions`): `INTERNET`,
`ACCESS_NETWORK_STATE`, `WAKE_LOCK`, `VIBRATE`, and the Firebase receive permission. No
"dangerous" permission: photos come through the system photo picker and the camera through the
system camera app, so there is no storage, camera or location grant. `POST_NOTIFICATIONS` is
removed on purpose (`tools:node="remove"` in `AndroidManifest.xml`) until Firebase exists, so no
one is asked to allow notifications they cannot receive.

**iOS**: `NSCameraUsageDescription` and `NSPhotoLibraryUsageDescription` (both say the photo is for
showing a store what is wrong with a returned item; English only, there are no localised
`InfoPlist.strings`); `UIBackgroundModes` `remote-notification` and `aps-environment` `production`
for push; `ITSAppUsesNonExemptEncryption` false (only standard TLS); App Transport Security at its
defaults (no cleartext exception: the live server serves https only). No
`NSUserTrackingUsageDescription`, because nothing tracks.

**When Firebase is configured**: delete the `POST_NOTIFICATIONS` removal in the manifest, add the
config files, turn on the Push capability for the App ID, then update sections 3 and 4 (Device ID)
and the privacy manifest if they changed.

## 6. Account deletion

Apple's Guideline 5.1.1(v) and Google's account-deletion policy both apply, because the app can
create accounts.

**In the app:** Account tab › **Privacy & data** (the row ends with the words "Delete account") ›
Delete my account › tick "I understand this can't be undone" › confirm. The app calls Magento's
`deleteCustomer`, then unregisters the push token and clears the sign-in token and the cart. If the
server refuses, the customer stays signed in and sees an error; it never pretends to have worked.
The Settings screen has the same action.

**What goes and what stays.** The account, saved addresses and wishlist are removed; order and
invoice records are kept for the period UAE law requires, and the dialog says so. **CONFIRM on
staging** what happens to the reviews the customer wrote and to their store credit balance: the
app tells the customer they lose both, but core `deleteCustomer` only deletes the customer record,
and Magento normally keeps a review (without its account link) when its author is deleted. If
reviews stay, the policy must say so.

**Known gaps to cover in the policy or fix later:**
- There is no "Download my data" (the store has no export endpoint), so the policy should say how
  to ask for a copy, and someone must own that request.
- Deletion needs no password (core `deleteCustomer` takes none, and customers who joined by
  WhatsApp code may not have one).
- Open orders are not checked before deletion (Magento does not enforce it).

**Lesson from Zoonze.** Apple rejected the Zoonze app under 5.1.1(v) because deletion was only
reachable through a row labelled "Language". Here the path is one tap from the Account tab and the
row names it; still state the path in the review notes and attach a screen recording made on a
physical device with a throw-away account (deletion is permanent). See
[app-review-notes.md](app-review-notes.md).

**Web page for Google Play.** Play's Data safety form needs a URL where people can ask for their
account and data to be deleted, also for someone who no longer has the app. Draft for a CMS page
(client publishes it and replaces the bracket):

```
Delete your Hub Market account

In the app: open the Account tab, tap Privacy & data, then Delete my account and confirm.
Your account, saved addresses and wishlist are removed. Order and invoice records are kept for
the period UAE law requires.

Without the app: e-mail [privacy contact address] from the address on your account, with the
subject "Delete my account". We answer within [period] and confirm when it is done.
```

```
حذف حسابك في Hub Market

من التطبيق: افتح تبويب «حسابي»، ثم اضغط «الخصوصية والبيانات»، ثم «حذف حسابي» وأكّد.
تُحذف بذلك حسابك وعناوينك المحفوظة وقائمة المفضّلة. أمّا سجلّات الطلبات والفواتير فتُحفظ
للمدة التي يفرضها القانون في دولة الإمارات.

بدون التطبيق: راسلنا على [عنوان البريد الخاص بالخصوصية] من البريد المسجّل في حسابك، وعنوان
الرسالة «حذف حسابي». نردّ خلال [المدة] ونؤكد لك عند اكتمال الحذف.
```

(The Arabic labels are the app's own: `navAccount`, `privacyDataTitle` and `deleteAccountAction`
in `lib/l10n/app_ar.arb`. Change them together if the app's wording changes.)

## 7. Ratings, audience and policy declarations

**Apple age rating.** Answer the questionnaire from the content: violence, sexual content,
profanity, horror, gambling, contests: none. **User-generated content: yes** (product reviews).
**Unrestricted web access: no**: the in-app browser stays inside the store's own domain
(`staysInApp` in `web_view_screen.dart`, with a test) and hands other sites to the system
browser. Expect a low rating; what the tool returns wins. Alcohol, tobacco and medical questions
depend on the client's catalogue (see the pharmacy note below).

**Google Play.** Target audience **18 and over**; not designed for children. Content rating
questionnaire (IARC), category Shopping: user-generated content yes (reviews); no digital
purchases; no location sharing. **Ads: none.** **App access:** everything except order history,
returns, credit and account settings is open without signing in; give the reviewer a demo account
(see the review notes). News, government, COVID and health-app declarations: no.

**User-generated content.** Reviews are held for approval before they show ("Your review is
awaiting approval"), which is the moderation both stores look for (Apple 1.2, Google's UGC
policy). Moderation is usually enough, but a reviewer may also expect a way to report content: if
App Review asks for one, add a "Report" action that opens the contact form with the review's id
filled in. No backend change is needed.

**Pharmacy and restricted goods (decision needed).** The test catalogue already has a seller in the
Pharmacy category. If real pharmacies will sell medicines through the app, both stores have rules
(Google Play's health and prescription-drug policies; Apple's Physical Harm section, 1.4, and
5.1.1(ix), which wants a legal entity for services in regulated fields) and may ask for licence documents. The same goes
for alcohol, tobacco and vaping products. The client must say what sellers may list, and the
answers above (age rating, content rating) follow from it.

**Store credit.** The credit can be bought in the app (Buy credit) and is spent only on physical
goods in the store. Google's financial-features declaration and Apple's payment rules (3.1.1, 3.1.3(e)) should
be read with that in mind; our reading is that no in-app purchase is needed because everything
sold is a physical product delivered outside the app. **CONFIRM** with the client's counsel and
answer the Play declaration truthfully.

**Apple 4.8 (Sign in with Apple)** does not apply: there is no third-party or social sign-in.

## 8. What the privacy policy must cover

The website's Privacy page still carries sample text; the stores need a real page that covers
the mobile app. It should say, in English and Arabic:

1. Who the controller is (legal entity, address, contact for privacy questions).
2. The data in section 1, and why each is used.
3. That sellers receive delivery details for their own orders, and who else is a recipient
   (section 2), including any transfer outside the UAE (Algolia, Firebase).
4. How long data is kept, including order and invoice records under UAE law.
5. The customer's rights (access, correction, deletion, and how to ask), under the UAE personal
   data protection law (Federal Decree-Law 45 of 2021: counsel to confirm the exact wording).
6. That the app does not track people or show ads, and does not read location or contacts.
7. Children: the app is for adults.
8. How changes are announced.

## 9. Open questions for the client

| # | Question | Our recommendation |
|---|---|---|
| 1 | Who publishes the privacy policy and the deletion page, and at which URLs? | Client's counsel; the URLs go into both stores. |
| 2 | Which legal entity owns the developer accounts (D-U-N-S), and will it be declared a trader for the EU? | The selling entity; a non-trader app disappears from EU storefronts. |
| 3 | Does the seller panel show buyers' email and phone? | Confirm, then keep "shared" as in section 4. |
| 4 | Sign Algolia's data-processing agreement; which region hosts the index? | Yes; name it in the policy. |
| 4b | Keep Algolia Analytics on for the app's searches? It shows which searches find nothing. | Keep it and say in the policy that Algolia keeps search terms and connection addresses for its analytics; or switch `analytics` off for those queries in `lib/features/catalog/data/algolia/algolia_search.dart` (a one-line change) and the search-history answer gets simpler. |
| 5 | Which provider delivers the WhatsApp or SMS codes? | Name it in the policy. |
| 6 | Add crash reporting (Firebase Crashlytics) before launch? | Optional. It would add "crash logs, diagnostics" and a device id to both forms and to the privacy manifest. |
| 7 | Return photos may carry GPS data from a phone camera. | Strip photo metadata on the server (a follow-up on the backend PR). |
| 8 | What may pharmacies and other restricted categories list? | Decide before the rating and policy forms. |
| 9 | Commit the Firebase config files or inject them from secrets? | **Decided 2 Oct 2026: inject from secrets, never commit** (`tool/firebase_config.sh`, `docs/release/README.md` section 3). The files are not secrets in themselves, but still restrict the API keys by package name and bundle id in Google Cloud. |
| 10 | Localise the iOS camera and photo prompts into Arabic? | Optional polish: add `InfoPlist.strings` for `ar`. |
