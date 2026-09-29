# App Information page — answers (v1.0.0)

Covers the **App Information** section in App Store Connect. Name and Subtitle
are already filled from `listing-en.md`; everything below is what's still blank
or needs a decision.

---

## Category

| Field | Value |
|---|---|
| Primary | **Shopping** |
| Secondary (optional) | **Lifestyle** |

Shopping is where a retail storefront belongs and is what beauty retailers
compete in. Avoid **Health & Fitness** as the secondary even though the app
sells skincare — it invites the medical questions in the age-rating
questionnaire and implies claims the app doesn't make.

---

## Content Rights

**Recommended answer: yes, it contains third-party content — and you have the
rights.**

The app displays manufacturer product photography, brand names and logos
(Gucci, Pixi and so on) served from the Magento catalog. That is third-party
content in Apple's sense, even though Zoonze is an authorised reseller
displaying goods it actually sells.

**This one is the owner's call, not a technical fact** — it asserts you hold
the necessary rights or permissions for that imagery. Confirm with whoever
manages the brand agreements before ticking it.

---

## Age Rating

Recommended answers. Expected result: **4+**, but see the blocker below.

| Question | Answer |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Alcohol, Tobacco, or Drug Use or References | None |
| Mature/Suggestive Themes | None |
| Horror/Fear Themes | None |
| Medical or Treatment Information | None |
| Gambling, Contests, Loot Boxes | None |
| Unrestricted Web Access | **No** (as of 1.0.0 build 77 — see below) |
| User-Generated Content | Yes — product reviews |

Notes on the two that aren't obvious:

- **Alcohol** — perfume is alcohol-based, but the question is about depicting or
  referencing alcohol *consumption*. None.
- **Medical or Treatment Information** — the app lists skincare products; it
  gives no diagnosis, dosage or treatment guidance. None. (This is also why
  Health & Fitness is the wrong secondary category.)
- **User-Generated Content** — customers can write product reviews
  (`createProductReview`). Reviews go through Magento's moderation queue rather
  than appearing instantly, which is what Apple cares about under Guideline
  1.2.

### "Unrestricted Web Access" — resolved in build 77

Builds up to **76** would have had to answer **Yes**, forcing a **17+** rating:
`WebViewScreen` set `JavaScriptMode.unrestricted` with a `NavigationDelegate`
that had **no `onNavigationRequest`**, so a link inside a CMS page could
navigate anywhere on the web under our app bar.

**Build 77 confines it.** `staysInApp` (`lib/core/widgets/web_view_screen.dart`)
allows main-frame navigation only within the store's own registrable domain;
other sites and non-http schemes (`mailto:`, `tel:`) hand off to the platform
browser. Sub-frames are never blocked, so embedded media in a CMS page still
renders. Covered by `test/core/widgets/web_view_navigation_test.dart`,
including lookalike hosts such as `zoonze.com.evil.example`.

So **No** is now an accurate answer, and the rating stays **4+**.

**Attach build 77 or later.** Apple tests this, and answering No on an earlier
build would be a false declaration.

---

## App Encryption Documentation

**Nothing to do.** `ITSAppUsesNonExemptEncryption` is already `false` in
`ios/Runner/Info.plist:11`, which answers the export-compliance question
automatically at upload. The app uses only HTTPS/TLS, which is exempt. No
document upload is needed.

---

## Digital Services Act — trader status

The page currently reads *"This developer has identified itself as a
non-trader for this app."* **That is wrong for this app and needs fixing, one
way or the other.**

Zoonze sells physical goods for profit, which makes it a trader under the DSA.
Apple **removes non-trader apps from all EU storefronts**.

**Decision: declare trader status** (owner, 2026-07-29), keeping the app
visible on EU storefronts for UAE expatriates and travellers browsing from EU
accounts. The rejected alternative was staying non-trader and restricting
availability to the UAE/GCC.

Completed by the owner in App Store Connect — it needs business identity
details and is a legal declaration, so it can't be scripted. Via the *Get
Started* link under Digital Services Act:

| Needed | Note |
|---|---|
| Legal entity name | Must match the D-U-N-S record on the developer account, not a trading name |
| Registered business address | Published publicly (see below) |
| Phone + email | Both receive a verification code |

Two things that catch people out:

- **The details are published** on the EU product page — that is the point of
  the requirement, so EU buyers can identify and contact the trader. Not a
  personal address or mobile.
- **Verification is not instant.** Apple checks against the D-U-N-S record; a
  mismatch (renamed entity, moved address) bounces it and the app stays off EU
  storefronts until it clears. Fix a stale D-U-N-S record first.

What is not acceptable is remaining non-trader *while* available in the EU —
the listing silently disappears there.

---

## Fields already correct

| Field | Value |
|---|---|
| Name | Zoonze |
| Subtitle | Beauty, Fragrance & Skincare |
| Bundle ID | com.zoonze.shop |
| SKU | zoonze-shop-001 |
| Primary Language | English (U.S.) |
| License Agreement | Apple's standard EULA is fine — the app has no custom licence terms |

Localizable fields (Name, Subtitle) also need an **Arabic** version once that
localization is added — see `listing-ar.md`.
