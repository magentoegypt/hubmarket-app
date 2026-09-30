# Deep links: `assetlinks.json` and the iOS association file

Store links (`https://<store host>/en/...`) open the app instead of the browser only when the
store's own web server publishes two small files. The app side is done; the files are the web
team's job, and they need two facts that only exist after the store accounts do: the Play
**app-signing certificate's SHA-256** and the Apple **Team ID**. Status on 29 Sep 2026: both files
answered 404 on `hub-market.magento2.click`, so every link opens the browser today. Check it any
time with `bash tool/verify_applinks.sh`.

## What the app already does

| | Android | iOS |
|---|---|---|
| Custom scheme | `hubmarket://app/...` (works today) | `hubmarket://app/...` (`FlutterDeepLinkingEnabled` is on) |
| Store links | https App Links with `autoVerify`, for the store host and its `www.` twin, limited to `/`, `/en/...`, `/ar/...` and root-level `*.html` (`AndroidManifest.xml`) | Universal links **not yet declared**: the Associated Domains block in `ios/Runner/Runner.entitlements` is commented out on purpose (see below) |
| What a link does | `DeepLinkResolverScreen` handles it on both platforms: the `/en/` or `/ar/` segment switches the app's language; `/shop/<code>/` opens the store page; product, category and CMS paths open the native screen; other pages on the store's domain open in the in-app browser (confined to that domain); a foreign host shows a not-found screen | same |

`/media`, `/static`, `/rest` and `/graphql` are deliberately not claimed: the app cannot route them.

## 1. Android: `assetlinks.json`

Publish at `https://<host>/.well-known/assetlinks.json` on **every host the manifest claims** (the
store host and its `www.` twin), answering `200` with `Content-Type: application/json`, with **no
redirect**:

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.hubmarket.app",
      "sha256_cert_fingerprints": [
        "<SHA-256 of the Play app-signing certificate>"
      ]
    }
  }
]
```

**Which fingerprint.** With Play App Signing (the default, and what the checklist assumes), Google
re-signs the app with its own key, so the fingerprint that matters is Play Console › Setup › **App
signing** › *App signing key certificate* › SHA-256, **not** the upload key's. Add the upload key's
too (`keytool -list -v -keystore <upload.jks>`) only if you also want links to open a build signed
with it. More than one fingerprint may be listed.

Until the `ANDROID_*` secrets exist, the Loadly test builds are signed with a debug key that changes
with every CI run, so App Links cannot verify on them: test links there with the custom scheme.
Once the secrets exist those builds carry the upload key, so list its fingerprint as well to test
App Links on Loadly, or test on the Play internal track, which carries the Play key.

## 2. iOS: `apple-app-site-association`

Publish at `https://<host>/.well-known/apple-app-site-association` on the same hosts, **no file
extension**, `Content-Type: application/json`, `200`, **no redirect** (Apple does not follow them),
valid TLS:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": ["<TEAMID>.com.hubmarket.app"],
        "components": [
          { "/": "/media/*", "exclude": true },
          { "/": "/static/*", "exclude": true },
          { "/": "/pub/*", "exclude": true },
          { "/": "/rest/*", "exclude": true },
          { "/": "/graphql", "exclude": true },
          { "/": "/" },
          { "/": "/en/*" },
          { "/": "/ar/*" },
          { "/": "/*.html" }
        ]
      }
    ]
  }
}
```

`<TEAMID>` is the ten-character Team ID from developer.apple.com › Membership; the entry must be
`<TeamID>.com.hubmarket.app` exactly. The paths mirror the Android filter.

**Enable it in the app, in this order** (an existing provisioning profile never picks up a new
capability, which is why the entitlement stays commented out until the last step). **Shortcut:** if
the App ID is created with **Associated Domains** already on, and the profiles are made after that,
steps 2 and 3 are already done. A profile that has a capability the app does not use is harmless, so
turn it on together with Push Notifications when the App ID is registered.

1. Publish the file on both hosts and check it with `IOS_TEAM_ID=<TEAMID> bash tool/verify_applinks.sh`.
2. developer.apple.com › Identifiers › `com.hubmarket.app`: turn on **Associated Domains**.
3. Regenerate the App Store and Ad Hoc provisioning profiles, and put the new ones in the
   `IOS_APPSTORE_PROFILE_BASE64` and `IOS_ADHOC_PROFILE_BASE64` secrets (CI re-signs from them, so
   an old profile would ship *without* the capability and links would silently keep opening Safari).
4. Uncomment the `com.apple.developer.associated-domains` block in `ios/Runner/Runner.entitlements`
   with the production hosts, and ship a new build.

Apple caches the file on its own CDN, so a change can take hours to reach phones. For a development
build, `applinks:<host>?mode=developer` skips the cache.

## 3. Check it

```bash
bash tool/verify_applinks.sh                      # both files, both hosts (set IOS_TEAM_ID for iOS)
adb shell pm get-app-links com.hubmarket.app      # Android 12+: state of each host (verified / none)
adb shell am start -a android.intent.action.VIEW -d "https://<host>/en/" com.hubmarket.app
```

On an iPhone, paste a store link into Notes and tap it: it should open the app, not Safari.

## When the domain changes

Everything above uses the store's host. Moving from `hub-market.magento2.click` to the production
domain means the two files on the new host (and its `www.` twin), the hosts in
`AndroidManifest.xml` and `Runner.entitlements`, and the list in the "Switch to the production
domain" section of [README.md](README.md).
