# Store screenshots

What each store wants, the shot list the app produces, and how to capture it. The pipeline works
on both platforms; the shots are **not store-ready** until the client's real catalogue is in the
store (see "What is not store-ready").

## Rules (as of 30 Sep 2026: re-check the console on the day)

| | Google Play | App Store |
|---|---|---|
| How many | 2 to 8 phone screenshots per language | 1 to 10 per language |
| Format | PNG or JPEG, 24-bit, **no alpha** | PNG or JPEG, **no alpha** |
| Size | 320 to 3840 px per side, and the long side **at most twice** the short side. 9:16 (1080×1920) is the safe size and the one needed to be featured. | The required iPhone set is either **6.9-inch** (1290×2796 or 1320×2868) or **6.5-inch** (1242×2688 or 1284×2778); the other sizes scale from it. The app is iPhone-only, so no iPad set. |
| Also | Feature graphic 1024×500 (required), icon 512×512 | App preview video optional |
| Languages | A separate set per language; use the English and Arabic sets | The same |

Both stores reject screenshots that show another platform's interface, placeholder or test text,
a price or claim the app does not honour, or private data.

## The shot list

Eight shots, in the order a visitor should meet them (the first two or three are what shows in the
listing and on the install sheet). Each is taken in English (`en-…`) and in Arabic (`ar-…`, mirrored).
Wishlist, cart and account are left out on purpose: a fresh install has nothing in them, so they
would only show empty states.

| File | Route | Shows |
|---|---|---|
| `01-home` | `/home` | Home: delivery strip, hero, rails |
| `02-deals` | `/deals` | Today's Deals with countdown, department chips and filters |
| `03-category` | `/category/MTQw` | A category listing (Fashion) |
| `04-product` | `/product/dress-code-2156` | A product page with "Sold by" and offers |
| `05-stores` | `/stores` | Stores, with rating and product counts |
| `06-store` | `/store/loly` | A store page (products, reviews, about) |
| `07-bundles` | `/bundles` | Bundle deals with the saving on each |
| `08-categories` | `/categories` | Category tiles |

The list is in `integration_test/screenshots_test.dart`; the category uid, the product url key and
the store code are three constants at the top of it, so re-pointing the shots at other content is a
three-line change.

## How to capture

**iOS (GitHub Actions, on a hosted Mac):** Actions › **Screenshots · iOS** › Run workflow, once with
`en` and once with `ar`. It boots an iPhone simulator, drives the app against the live server, and
uploads the artifact `appstore-screenshots-ios-<locale>`: PNGs scaled to 1284×2778, the 6.5-inch
slot. The script fails when two shots are identical (a navigation that silently did not happen).

**Android (a phone or emulator on this machine):**

```bash
bash tool/android_screenshots.sh                  # English, dev flavor, the one attached device
SHOT_LOCALE=ar bash tool/android_screenshots.sh   # Arabic
```

It builds the debug dev flavor, drives the same integration test, and writes the raw captures to
`build/screenshots/android/raw` and Play-ready copies to `build/screenshots/android/play`.
`tool/fit_play_screenshots.py` scales a tall phone capture to fit Play's 2:1 limit on the brand navy
without cropping (a 1080×2400 capture becomes 1080×2160). **The phone must be unlocked with the
screen on for the whole run**: a sleeping screen draws no frames, and the test just waits. Use
`Stay awake` in Developer options while it runs.

## What is not store-ready

1. **The catalogue is test data.** Store names such as "Test 1" and "Test3", products named
   "test61", placeholder photos, a Pharmacy store used for tests. Capture again once the client's
   real, well-photographed products and stores are in, and point the three constants at good ones.
2. **Arabic needs Arabic content.** The Arabic set shows product and store names as the catalogue
   holds them; some are English only today.
3. **Framing.** Store pages convert better with a headline above the screen. That is design work:
   framed screenshots and the Play feature graphic (brand navy `#0F2144`, orange `#F26522`, the
   logo) come from Figma, using these captures as the source.
4. **Re-capture on every release that changes the UI.**
