# Release readiness (P4)

Everything needed to take the Hub Market app from the QA link to Google Play and the App Store,
split into what is **ready in the repo**, what **the client has to provide**, and the **steps**
once they have. It was written on 30 Sep 2026 from the workflows, the Gradle and Xcode projects and
the code, not from memory. Nothing here publishes anything or creates an account.

| File | What it holds |
|---|---|
| this file | status, what we need, the secrets map, the first Android and iOS release, the domain switch, the pre-flight |
| [store-listing.md](store-listing.md) | English and Arabic listing text for both stores, with limits checked |
| [privacy-and-data-safety.md](privacy-and-data-safety.md) | what the app collects, Apple's App Privacy and Google's Data safety answers, deletion, ratings |
| [app-review-notes.md](app-review-notes.md) | the Notes box for App Review and Play's App access text |
| [deep-links.md](deep-links.md) | `assetlinks.json` and the iOS association file, ready to publish once the ids exist |
| [screenshots.md](screenshots.md) | store screenshot rules, the shot list, how to capture on both platforms |

## 1. Where things stand

| Area | State |
|---|---|
| Android build | Every push to `main` (except `[skip ci]`) runs the gate, builds the production APK and updates the Loadly link. It is **debug-signed** until the upload-keystore secrets exist. The same push also builds the Play bundle and uploads it to **internal testing** once that is switched on (section 3b). `Release · Android` stays for a one-off bundle; its `.aab` packaging step has **not been run yet**, so step 4 of the first release doubles as its dry run. |
| iOS build | Every push to `main` builds the signed App Store IPA and uploads it to **TestFlight** (the first one, 1.0.0 (1), went through on 30 Sep 2026), and, once `IOS_ADHOC_PROFILE_BASE64` exists, an ad-hoc IPA to Loadly (section 3b). **The Apple side is set up:** the App ID `com.hubmarket.app` (Push Notifications and Associated Domains on), an App Store profile and the App Store Connect app record "Hub Market". `Release · iOS` stays for one-off runs. |
| Identity | Android `com.hubmarket.app` (`.dev` and `.staging` for the other flavors); iOS `com.hubmarket.app`; name "Hub Market"; version `1.0.0+1`; Android compile and target SDK 36; iOS 15 and up, iPhone only; portrait only (Android manifest, iOS Info.plist). |
| Icon and launch screen | Client artwork, correct formats (1024×1024 icon with no alpha; adaptive Android icon; native launch screen). Not present: the Play **feature graphic** (1024×500). |
| Listing text, privacy answers, review notes | Drafted in English and Arabic (files above); each needs the client to confirm the facts it lists. |
| iOS privacy | An app privacy manifest is in the project, and the leftover cleartext (HTTP) exception from the Zoonze base is gone: the live server serves only HTTPS. |
| Screenshots | Capture pipeline for both platforms (iOS captured in English and Arabic; Android waits for an unlocked phone). The catalogue is still test data and the hero and seller profiles still say Egypt, so the shots are not store-ready. |
| Deep links | Templates ready; blocked on the Play signing SHA-256, the Apple Team ID and the web team. |
| Push notifications | Dormant until a Firebase project exists (section 6). |
| Payment | Cash on delivery only. Card, Tabby and Tamara wait on DEV08 and DEV09. |

## 2. What we need from the client

**Accounts**
1. A **Google Play Console** developer account (an organisation account, verified) and who gets access.
2. An **Apple Developer Program** membership (organisation) with App Store Connect access; the
   ten-character **Team ID**.
3. A **Firebase project** for push (Android and iOS apps registered with the two ids above).

**Decisions**
4. ~~The store **name**~~ Decided: **Hub Market** (30 Sep 2026; "ME Hub Market" from DEV03 is dropped).
5. The **production domain**. `hub-market.magento2.click` is a `magento2.click` development domain
   with a wildcard certificate; the app and the links are tied to whatever host is chosen
   (section 5).
6. The **payment path** for launch (cash on delivery only, or card, Tabby, Tamara).
7. What **pharmacies and other restricted categories** may list (privacy document, section 7).
8. **Crash reporting** (Firebase Crashlytics) before launch, yes or no: it changes the privacy answers.
9. Firebase config files **committed or injected from secrets** (privacy document, question 9).

**Content and legal**
10. A real **privacy policy** and a **terms page**, English and Arabic, and a **deletion page** URL.
11. **Support** email, phone and website; the **legal entity** (D-U-N-S) and its trader details for
    the EU Digital Services Act.
12. A **demo account** on the server the release talks to, with a past order, for the reviewers.
13. The **real catalogue** (photographed products, real stores, Arabic names) for the screenshots,
    and a **feature graphic** plus framed screenshots from design.

**Backend and admin** (the QA list, section C, has the same items with where to find them)
14. Order cancellation on; UAE postcode optional; the `hm_app_faq` block; the WhatsApp number in
    `hm_footer_customer` (a US number today); test products off; the "across Egypt" text replaced.
15. `assetlinks.json` and the iOS association file published ([deep-links.md](deep-links.md)).
16. On the production server: strip photo metadata from return photos (a follow-up on the backend
    PR), let the app's `HubMarketApp/<version>` user agent through the WAF, and keep any cache in
    front of `GET /graphql` varying on the `Store` header.

## 3. Secrets and files: what feeds what

Repository secrets live under GitHub › repo › Settings › Secrets and variables › Actions. The
person who holds a secret sets it; **it is never pasted into a chat, a ticket or the repo**, which
is public. Encode a file with `base64 -w0 <file>` (Linux, Git Bash) or `base64 -i <file>` (macOS).

**Android**

| Secret | Used by | What it is and how to make it |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | `Release · Android`, and every push build once set | The upload keystore, base64. Create once: `keytool -genkey -v -keystore hubmarket-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hubmarket`. Keep the `.jks` and both passwords in the company password manager. |
| `ANDROID_STORE_PASSWORD` | same | The store password chosen in `keytool`. |
| `ANDROID_KEY_PASSWORD` | same | The key password chosen in `keytool`. |
| `ANDROID_KEY_ALIAS` | same | `hubmarket` if the command above was used. |
| `PLAY_SERVICE_ACCOUNT_JSON` | `Release · Android`, only when `play_track` is not `none` | A Google Cloud service-account key (JSON). In Play Console › Users and permissions, invite the service account's email and give it release rights on the app; create the key in Google Cloud › IAM › Service accounts. |
| `LOADLY_API_KEY` | push builds, `Release · Android` (apk) | Already set; uploads the QA build. |

**Setting the keystore secrets changes the signature of the Loadly build.** Testers who installed a
debug-signed build must uninstall it once, or Android refuses the update.

**iOS**

| Secret | Used by | What it is and how to make it |
|---|---|---|
| `IOS_P12_BASE64`, `IOS_P12_PASSWORD` | `Release · iOS`, `Build · iOS` | The Apple Distribution certificate with its private key. With no Mac: `bash tool/ios_make_csr.sh --email <apple id> --name "Hub Market" --country AE`, upload the request at developer.apple.com › Certificates › Apple Distribution, then bundle the downloaded `.cer` with the key into a `.p12` (the script prints the two `openssl` commands). |
| `IOS_APPSTORE_PROFILE_BASE64` | `Release · iOS` (`testflight`) | An **App Store** provisioning profile for `com.hubmarket.app`: Profiles › + › App Store Connect, pick the App ID and the certificate, download the `.mobileprovision`. |
| `IOS_ADHOC_PROFILE_BASE64` | `Release · iOS` (`adhoc`), `Build · iOS` | Optional: an **Ad Hoc** profile listing the test devices' UDIDs, for installing on phones without TestFlight. |
| `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_CONTENT_BASE64` | `Release · iOS` (`testflight`) | App Store Connect › Users and Access › Integrations › App Store Connect API: create a key with the App Manager role; copy its Key ID and the Issuer ID; download the `.p8` (once) and base64 it. |

**Files that are not secrets but do not exist yet** (push): `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist`. See section 6.

## 3b. Automatic deployment on every push to main

`.github/workflows/build-on-push.yml` runs on every push to `main` (put `[skip ci]` in a commit
message to skip it) and deploys the same commit everywhere it can:

| Step | Needs | State |
|---|---|---|
| Gate: analyze, tests, tool tests, offline GraphQL check | nothing | always |
| Android APK → Loadly | `LOADLY_API_KEY` | on |
| iOS App Store IPA → TestFlight | the six `IOS_*` and `APP_STORE_CONNECT_*` secrets | on |
| iOS ad-hoc IPA → Loadly | `IOS_ADHOC_PROFILE_BASE64`, the two p12 secrets, `LOADLY_API_KEY` | waits for the ad-hoc profile secret |
| Android app bundle → Google Play internal testing | the four `ANDROID_*` secrets, `PLAY_SERVICE_ACCOUNT_JSON`, and the repository variable `PLAY_AUTO_PUBLISH` = `true` | off until the first release was uploaded by hand |

**One Loadly link for both platforms.** The Android and iOS apps are *combined* in Loadly (Loadly ›
the app › Combine; **Separate** undoes it), so the link https://loadly.io/7ino6c4V and its QR code
install the right build for the phone that opens it, and the page also offers both downloads. New
uploads from CI keep updating the same two apps, so the combination stays.

A step whose secrets are missing is skipped with a notice that names them, so the file stays as it
is while accounts arrive. To pause the TestFlight, iOS Loadly and Play uploads without editing
anything, set the repository variable `DEPLOY_ON_PUSH` to `false` (`gh variable set DEPLOY_ON_PUSH
--body false`; delete it to resume). The Android Loadly upload always runs. A newer push cancels an
older run that is still going, so only the latest commit is deployed.

**Build numbers.** Every build gets `tool/build_number.sh`, the number of commits on `main`, so each
upload is higher than the last, as App Store Connect and Google Play require. The `+N` in
`pubspec.yaml` only matters for local builds. The manual workflows use the same rule, so they never
collide with the automatic ones. The marketing version (`x.y.z`) is still a `pubspec.yaml` edit.

**TestFlight testers.** Internal testers need a TestFlight group (Create Group, in the app's
TestFlight tab) with *automatic distribution* on; otherwise each build has to be added by hand.

## 4. First Android release

1. **Play Console:** create the app (name, English as the default language, Arabic as a second,
   App, free), then fill the *App content* pages with the answers in
   [privacy-and-data-safety.md](privacy-and-data-safety.md) and [app-review-notes.md](app-review-notes.md).
2. **Upload key:** generate the keystore (section 3) and set the four `ANDROID_*` secrets. Enrol in
   **Play App Signing** when Play offers it (the default for new apps).
3. **Version:** in `pubspec.yaml`, `version: 1.0.0+N`. `N` becomes the Play `versionCode` and must
   be higher than any upload before it. Commit it.
4. **Build:** Actions › **Release · Android** › Run workflow: flavor `prod`, output `aab`, publish
   `none`. Download the `appbundle-prod` artifact.
5. **First upload by hand:** Play refuses an API upload for a package that has never been released.
   In Play Console › Testing › **Internal testing**, create a release and upload that bundle; add the
   testers' emails.
6. **From then on:** set the repository variable `PLAY_AUTO_PUBLISH` to `true`
   (`gh variable set PLAY_AUTO_PUBLISH --body true`): every push to `main` then uploads the bundle to
   internal testing (section 3b). The same workflow with `play_track` (`internal`, `alpha`, `beta`)
   still works for one-offs. Only `prod` may publish (the other flavors are different packages).
7. **App Links:** copy the **App signing key certificate SHA-256** from Play Console › Setup › App
   signing to the web team for `assetlinks.json` ([deep-links.md](deep-links.md)).
8. **Store listing:** paste the text from [store-listing.md](store-listing.md) in both languages,
   add the icon, feature graphic and 2–8 phone screenshots per language ([screenshots.md](screenshots.md)).
9. **Production:** promote the tested release. A **personal** developer account created after
   Nov 2023 must first run a closed test with at least 12 testers for 14 days; an organisation
   account does not. Prefer a staged rollout.

Play needs a 64-bit `.aab` targeting a recent API level; the project targets 36.

## 5. Switch to the production domain

The app talks to `https://hub-market.magento2.click/graphql` and claims that host for links. If the
client launches on another domain, change all of these together and rebuild:

| Where | What |
|---|---|
| `config/prod.json`, `config/staging.json`, `config/dev.json` | `GRAPHQL_ENDPOINT` |
| `lib/core/config/app_config.dart` | the default GraphQL endpoint (line 79) |
| `lib/features/catalog/presentation/storefront_links.dart` | the host test for "our own domain" (line 310) |
| `android/app/src/main/AndroidManifest.xml` | the two hosts of the App Links filter |
| `ios/Runner/Runner.entitlements` | the commented `applinks:` domains, when universal links are enabled |
| `tool/verify_applinks.sh` | the default `HOSTS` |
| `tool/introspect_to_sdl.py`, `tool/validate_ops.py` | the endpoint the schema is read from |
| `.github/workflows/screenshots-ios.yml`, `pubspec.yaml`, `CLAUDE.md`, `README.md` | wording only |
| Tests | many use the current host as a fixture; they keep passing and can stay |

Also on the new host: a certificate that covers it (ATS is at its defaults, so TLS 1.2+ is needed),
the WAF rule for the app's user agent, the `Store` header in any cache or CDN, and the two
well-known files. Algolia is found through the storefront page (`window.algoliaConfig`), so it
follows the host. So do the WebP copies of product images: the app asks the GraphQL host for
`<resized image>.webp` and falls back to the original on any failure, so a host without them still
works (one extra request per image); check with `curl -I` on a resized product image plus `.webp`.

## 6. Turning on push (when the Firebase project exists)

1. Register the Android package `com.hubmarket.app` and the iOS bundle `com.hubmarket.app` (and
   `.dev` / `.staging` if those flavors should receive push) in the Firebase project.
2. Add `android/app/google-services.json` (the Gradle plugin turns on by itself when it exists) and
   `ios/Runner/GoogleService-Info.plist`. On iOS the plist must be in the Runner target's *Copy
   Bundle Resources*: add it in Xcode, or ask us to add the project reference. The app initialises
   Firebase from the bundled file only, never from options compiled into the code.
3. Delete the `POST_NOTIFICATIONS` removal element at the top of `AndroidManifest.xml`; the app then
   asks once on Android 13+.
4. Upload an **APNs authentication key** to Firebase (Cloud Messaging › Apple app configuration) and
   make sure the App ID has the Push Notifications capability (the entitlement `aps-environment`
   is already `production`).
5. Set the push (FCM) settings in the store admin so the server can send.
6. Update the privacy answers: Device ID (both forms, and the manifest if it changed).

## 7. Before every submission

- `flutter analyze` and `flutter test` clean; `PYTHONIOENCODING=utf-8 python tool/validate_ops.py`
  reports 0 problems; CI green on `main`.
- **Version numbers.** CI numbers every build by the commit count (section 3b), so the `+N` in
  `pubspec.yaml` does not matter for CI builds. The marketing version (`x.y.z`) does: once a version
  has been through App Store review or release its train is **closed**, and the next upload needs a
  new `x.y.z`, not just a new build number (Zoonze hit exactly this). Bump it in `pubspec.yaml`.
- A real-device pass on the **release** build (the signed one): sign in, guest checkout on cash on
  delivery, deletion of a throw-away account, English and Arabic, a store link.
- Listing, screenshots and review notes match the build being submitted.
- The demo account works on the server the build uses.
- Privacy forms match the build (new SDK, new permission, new data means a new answer).

## 8. Later

- **Forced update and maintenance mode** need no release: the admin sets a minimum app version
  and a maintenance switch; the app shows a full-screen page (`hmAppConfig`).
- No crash reporting ships today, so a crash is only seen if a customer reports it. Decide on
  Crashlytics (item 8 in section 2) before the first release rather than after.
- Home banners, sections, brands and texts are managed in the store admin; a marketing change is
  not an app release.
- Platform requirements move every year: Apple raises the minimum SDK each spring (CI builds with
  the latest stable Xcode on `macos-15`, which is what it needs), Google raises the minimum target
  API each August (the project targets 36), and Google has announced developer verification for apps
  installed outside Play, which is rolling out country by country: check it for the countries the
  Loadly testers are in.
