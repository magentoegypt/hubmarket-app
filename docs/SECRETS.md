# GitHub Actions secrets — full reference

Add these under **GitHub → repo → Settings → Secrets and variables → Actions →
New repository secret**. Each row says exactly how to produce the value. Grouped
by what they unlock; only group 1 is needed to ship a signed iOS build.

---

## 1. iOS ad-hoc IPA (signed) — every push · **1 secret + 2 files**

Used by `build-on-push.yml`. Produces a signed `ipa-prod` you can install OTA
(AppsOnAir / Diawi) on registered devices. **No fastlane `match` / `MATCH_*`.**

### Files to commit (not secrets) — in `ios/signing/`

**`ios/signing/<anything>.p12`** — your Apple **Distribution** certificate *with
its private key*:
1. If you don't have a distribution cert yet: developer.apple.com → Certificates,
   Identifiers & Profiles → **Certificates → +** → **Apple Distribution** →
   upload a CSR (Mac: *Keychain Access → Certificate Assistant → Request a
   Certificate From a Certificate Authority* → "Saved to disk"; **no Mac:** run
   `tool/ios_make_csr.sh --email you@apple-account.com` — produces the same
   `.certSigningRequest` + a private key via openssl) → download the `.cer` and
   double-click to add it to Keychain.
2. Export it: **Keychain Access → My Certificates** → right-click *"Apple
   Distribution: …"* (it must show a disclosure triangle = has the private key) →
   **Export…** → save as `.p12` → **set a password** (you'll put that password in
   `IOS_P12_PASSWORD`).
3. Drop the `.p12` into `ios/signing/`.

**`ios/signing/<anything>.mobileprovision`** — an **ad-hoc** provisioning profile:
1. developer.apple.com → **Identifiers** → confirm the App ID `com.zoonze.shop`
   exists.
2. **Devices** → register each test device's **UDID** (get it from the device:
   Finder/iTunes, or Settings → General → About → tap the serial, or Xcode).
3. **Profiles → +** → Distribution → **Ad Hoc** → pick App ID `com.zoonze.shop`
   → pick the Distribution certificate above → select the devices → name it →
   **Generate** → **Download** the `.mobileprovision`.
4. Drop it into `ios/signing/`.

> The filenames don't matter — the build picks the first `*.p12` and first
> `*.mobileprovision` and reads team id / bundle id / profile name automatically.

### Secret

| Secret | How to produce |
|---|---|
| `IOS_P12_PASSWORD` | the password you chose when exporting the `.p12` in step 2 above |

---

## 2. Android — Play-uploadable signed APK · optional (4)

Used by `build-on-push.yml` + `release-android.yml`. Without these the APK is
**debug-signed** — it still installs for testing/AppsOnAir, just isn't
Play-uploadable.

Create the keystore once:
```bash
keytool -genkey -v -keystore zoonze-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias zoonze
# choose a store password + key password; fill in the name/org prompts
```

| Secret | How to produce |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | base64 of the keystore file. Linux: `base64 -w0 zoonze-release.jks` · macOS: `base64 -i zoonze-release.jks \| tr -d '\n'` |
| `ANDROID_STORE_PASSWORD` | the **store** password you set in `keytool` |
| `ANDROID_KEY_PASSWORD` | the **key** password you set in `keytool` (often the same) |
| `ANDROID_KEY_ALIAS` | the alias — `zoonze` if you used the command above |

---

## 3. TestFlight / App Store — `release-ios.yml` only · optional (7)

The **manual** App Store/TestFlight path (fastlane + `match`). **Not** needed for
the ad-hoc IPA in group 1.

| Secret | How to produce |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect → **Users and Access → Integrations → App Store Connect API** → create a key (role *App Manager*) → **Key ID** |
| `APP_STORE_CONNECT_ISSUER_ID` | same page → **Issuer ID** (top of the keys list) |
| `APP_STORE_CONNECT_KEY_CONTENT_BASE64` | download that key's `AuthKey_XXXX.p8` (one-time) → `base64 -w0 AuthKey_XXXX.p8` (macOS: `base64 -i … \| tr -d '\n'`) |
| `MATCH_GIT_URL` | create an **empty private git repo** to hold the encrypted certs/profiles → its clone URL |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `printf 'USERNAME:GITHUB_PAT' \| base64` — a PAT with read/write to the match repo |
| `MATCH_PASSWORD` | a passphrase **you choose** to encrypt the match repo |
| `APPLE_TEAM_ID` | developer.apple.com → **Membership** → **Team ID** (10 chars) |

One-time seed (any machine with Ruby, in `ios/`): `bundle install` then
`bundle exec fastlane match appstore`.

---

## 4. Live GraphQL introspection — `introspect.yml` only · optional (1)

| Secret | How to produce |
|---|---|
| `ZOONZE_API_TOKEN` | a Magento bearer token for authenticated introspection — generate from Magento Admin → **System → Integrations** (Access Token), or a customer token via `generateCustomerToken`. **Optional**: store discovery is a public query; the token is only forwarded for authenticated checks. |

---

## Quick map: which secret feeds which workflow

| Secret / file | build-on-push | release-android | release-ios | introspect |
|---|:--:|:--:|:--:|:--:|
| `ios/signing/*.p12` + `*.mobileprovision` + `IOS_P12_PASSWORD` | ✅ (iOS) | | | |
| `ANDROID_*` (4) | ✅ (APK, optional) | ✅ | | |
| `APP_STORE_CONNECT_*` + `MATCH_*` + `APPLE_TEAM_ID` | | | ✅ | |
| `ZOONZE_API_TOKEN` | | | | ✅ (optional) |

**To ship now:** group 1 only. Everything else is optional.
