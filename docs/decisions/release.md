# Decision — Release, flavors & deep links (Phase 5)

## App id & flavors  ✅ wired
- **applicationId `com.zoonze.shop`** (decided). The internal Kotlin `namespace`
  stays `com.zoonze.zoonze_app` (invisible to users; avoids moving sources).
- Three Android product flavors are wired in `android/app/build.gradle.kts`:
  `prod` (`com.zoonze.shop`), `dev` (`.dev`), `staging` (`.staging`) — so all
  three install side-by-side. Build/run **must pass a flavor**, e.g.
  `flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=config/dev.json`.
- Dart side: `config/<flavor>.json` + `lib/main_{dev,staging,prod}.dart` (present).
- **iOS schemes** per flavor are added in Xcode (macOS — owner step).
- **Firebase note:** because the flavors have distinct ids, register **all three**
  ids in the Firebase project (or only build the ones you register) — the
  google-services plugin fails on an unregistered id.

## Deep links
- `go_router` is the deep-link target. Android `AndroidManifest.xml` declares:
  - custom scheme `zoonze://app/...`
  - https app links for `https://zoonze.com/...` (`android:autoVerify="true"`).
- **App-links verification** ✅ done — `assetlinks.json` is live on `zoonze.com`
  and `www.zoonze.com` for `com.zoonze.shop`, carrying the **Play app-signing**
  SHA-256 (not the upload key). Verified live 2026-08-22 with
  `bash tool/verify_applinks.sh`.
- iOS Universal Links ⛔ still open — the AASA path currently 301s to the
  storefront, and the entitlement is staged (commented) in
  `ios/Runner/Runner.entitlements` pending an App ID capability + profile
  regeneration. Runbook in `docs/decisions/deep-links.md`.
- Payment return URLs (Phase 3) should reuse a deep-link-friendly return path so
  the N-Genius/Tabby WebView and push routing stay consistent.

## Signing  (gradle wired ✅ · owner supplies the keystore)
- **Android — gradle is wired**: `signingConfigs.release` reads `android/key.properties`
  (git-ignored) and the release build type uses it; with no `key.properties` it
  falls back to the debug key so the repo still builds. Owner steps:
  1. `keytool -genkey -v -keystore zoonze-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias zoonze`
  2. copy `android/key.properties.example` → `android/key.properties` and fill it.
  3. `flutter build appbundle --flavor prod -t lib/main_prod.dart --dart-define-from-file=config/prod.json`.
- **iOS:** signing certificates + provisioning profiles in Xcode / App Store Connect.

## FCM  (gradle wired ✅ · owner supplies config)
- The **Google Services** Gradle plugin is applied **only when**
  `android/app/google-services.json` exists (so the repo builds without it).
- Owner: create the Firebase project, register the app id(s), drop
  `google-services.json` into `android/app/` and `GoogleService-Info.plist` into
  `ios/Runner/` (via Xcode), add an APNs key + iOS Push/Background-Modes
  capabilities. `NotificationService` then enables FCM with no Dart changes.

## Permissions / config already wired
- `INTERNET` + `POST_NOTIFICATIONS` in `AndroidManifest.xml`; app label
  "ZoonZE Beauty".
- User-Agent header (`ZoonzeApp/<version>`) set on GraphQL requests — coordinate
  the CloudFront `/graphql` POST behavior + WAF allow-rule (Open Q §11).

## Store listing
- **Launcher icon — tooling wired**: `flutter_launcher_icons` is configured in
  `pubspec.yaml` (adaptive background = brand `#9E1B3F`). Owner: drop a 1024×1024
  `assets/branding/app_icon.png`, then `dart run flutter_launcher_icons`.
- Bundle store screenshots (EN + AR) and copy; privacy policy URL; Play Console /
  App Store Connect accounts + data-safety / app-privacy forms (Open Q §9).

## Version trains (App Store Connect)

TestFlight uploads are rejected once a **marketing version** is closed:

```
Validation failed (409) Invalid Pre-Release Train.
The train version '1.0.0' is closed for new build submissions
```

Hit on 2026-08-20 uploading 1.0.0+85. App Store Connect closes a train once that
version has been through review/release, and no further builds may go up under
it — **bumping only the build number (+N) cannot fix this**, the `x.y.z` has to
move too. 1.0.0 is closed; releases continue from 1.0.1.

So there are two independent rules, and both apply:

- **build number (+N)** must increase for every upload within a train — and Play
  applies the same rule to `versionCode` on a track;
- **marketing version (x.y.z)** must move to a new train once the previous one
  is closed.

## Play publishing

`Release · Android` can publish the .aab itself — set `play_track` to
`internal` (the TestFlight analogue), `alpha` or `beta`. Default `none` builds
the artifact only. Needs the `PLAY_SERVICE_ACCOUNT_JSON` repo secret (a Play
"Release manager" service account), and the app must already have one bundle
uploaded by hand — Play refuses API uploads for a package that has never been
published. Only `flavor=prod` may publish; dev/staging carry
`applicationIdSuffix`, so they are a different package to Play.

Unlike iOS, this is **not** automatic on push: both platforms publish only from a
manually dispatched release workflow.

## Pre-release QA checklist
- EN/LTR + AR/RTL sweep of every screen (the design specifies a full 52-frame
  mirror); confirm directional layout, Cairo for AR, Western numerals.
- `flutter analyze` clean, `flutter test` green, and the on-network smoke test
  (`tool/introspect.sh` + diagnostics screen).
