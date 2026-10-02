# Store screenshots

What each store wants, the shot list the app produces, how to capture it, and where it stands. The
pipeline works on iOS and is ready on Android; the shots are **not store-ready** until the client's
real catalogue is in the store (see "What is not store-ready").

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
| `01-home` | `/home` | Home as the admin has arranged it (search, delivery strip, hero, promo tiles, categories) |
| `02-brands` | `/brands` | Brands: logos with product counts, the A-Z strip and brand search |
| `03-category` | `/category/MTQy` | A category listing (Men's Clothing): price and filter chips, ratings, discounts and the seller of each product |
| `04-product` | `/product/dress-code-2156` | A product page with "Sold by", the store's rating and the price on the Add to Cart button |
| `05-stores` | `/stores` | Stores: chips with counts, the featured store, ratings and product counts |
| `06-store` | `/store/loly` | A store page: rating, products, "Contact vendor", tabs |
| `07-search` | `/search` (the term in `extra`) | Search results for "samsung", answered by Algolia like the website |
| `08-categories` | `/categories` | Category tiles |

Today's Deals and Bundle deals were in the 30 Sep list; they are out of it because the live deals
and the only bundle are test items (a black "Test" picture). Put `/deals` and `/bundles` back once
the store has real ones.

The list is in `integration_test/screenshots_test.dart`; the category uid, the product url key, the
store code and the search term are four constants in front of it, so re-pointing the shots at other
content is a four-line change. One thing to know when picking them:

- **The live server is slow on the first call**, so the category, product and search shots wait
  20-24 s. The test prints `IMAGES <shot>: n painted, m pending <urls>` for each shot, so a blank
  photo in a capture shows up in the log.
- **The "Personalise my picks?" sheet** opens over the Home of a fresh install. The test writes the
  answer "Not now" into the cache before it starts, so the shots show the shop and the Picked For You
  section is the top-rated list (a real shopper's own picks need their consent and about an hour).

## How to capture

**iOS (GitHub Actions, on a hosted Mac):** Actions › **Screenshots · iOS** › Run workflow, once with
`en` and once with `ar` (about 18 minutes each). It boots an iPhone simulator, drives the app
against the live server, and uploads the artifact `appstore-screenshots-ios-<locale>`: PNGs scaled to
1284×2778, the 6.5-inch slot. The script fails when two shots are identical (a navigation that
silently did not happen). The PNGs carry an opaque alpha channel; before uploading them to App
Store Connect drop it with
`python tool/fit_play_screenshots.py --flatten-only <folder> <out folder>`.

**Android (a phone or emulator on this machine):**

```bash
bash tool/android_screenshots.sh                  # English, dev flavor, the one attached device
SHOT_LOCALE=ar bash tool/android_screenshots.sh   # Arabic
```

It builds the debug dev flavor, drives the same integration test, and writes the raw captures to
`build/screenshots/android/raw` and Play-ready copies to `build/screenshots/android/play`.
`tool/fit_play_screenshots.py` scales a tall phone capture to fit Play's 2:1 limit on the brand navy
without cropping (a 1080×2400 capture becomes 1080×2160). **The phone must be unlocked with the
screen on for the whole run**: a sleeping screen draws no frames and the test just waits. Turn on
*Stay awake* in Developer options while it runs.

A phone whose OS asks for a tap on Install every time (HyperOS) gives `flutter drive` only three
unanswered prompts. For it run `TARGET=integration_test/device_check_test.dart SHOT_LOCALE=en
AUDIT_ONLY=zzz bash tool/device_audit.sh` instead (`SHOT_LOCALE=ar` for Arabic, one tap each): it
builds first and keeps offering the APK for about 12 minutes until someone taps Install, and
`AUDIT_ONLY=zzz` skips the audit scenes ([../device-audit.md](../device-audit.md)). The raw captures
land in `OUT_DIR`; fit them with `tool/fit_play_screenshots.py` as above.

The captures show the app only: the system status bar is not part of them, so the top band of each
shot is empty. A framed screenshot covers it with the headline.

## Where it stands (1 Oct 2026)

Both stores' sets are captured on the shot list above, after the Figma UI audit and the device-audit
fixes, so the 30 Sep sets (which still had Today's Deals and Bundle deals) are out of date:

- **iOS:** English run 36848770120 and Arabic run 36859104297 (`Screenshots · iOS`, both succeeded, on
  `main` d886422): 8 screenshots each, 1284×2778 (the 6.5-inch slot), alpha dropped with `--flatten-only`.
- **Android:** captured on a Redmi 24116RNC1I (Android 16, **720×1640**) from `main` e043a8c, English
  and Arabic, 8 screenshots each, every photo painted (the log's `IMAGES` lines say so). The phone's
  native width is below Play's 1080 px featuring size, so `fit_play_screenshots.py` scales each capture
  onto a 1080×2160 canvas with a navy band at each side; for sharper Play images capture on a 1080p
  phone or an emulator (`wm size` is not changed by the script).
- All four sets show what the live server holds that day (test data, see below); nothing was edited.

## What is not store-ready

The captures show what the live server holds today, which is test data mixed with the client's
first content:

1. **Test data.** Products named "test61" and "Test Product 2" with a black "Test" image or a
   photographed order slip as their picture, "test Bundle Product" sold by "V8S2", stores named
   "Test 1" and "Test3", a Pharmacy store used for tests. The bundles shot (`07`) is the weakest
   until real bundles exist.
2. **Content that names the wrong market.** The hero says "Fashion From Approved Egyptian Sellers"
   and the store page says "Giza, Egypt". These come from the admin (Hero Banner, the seller
   profile), not the app.
   **The delivery strip changed after the first captures.** The `01-home` shots of 2 Oct show it on two
   lines ("… orders · Fast nationwide shipping"). The Figma draws one line, so the app now shows the
   first clause of the `hm_delivery_promise` block ("Free delivery on qualifying orders"). Re-capture
   `01-home` (both platforms, both languages) from a build with that change before submitting, and
   replace it in Play Console and App Store Connect.
3. **Arabic needs Arabic content.** The Arabic set shows product and store names as the catalogue
   holds them; some are English only. One known cosmetic issue: the Arabic category tile's second
   line is cut ("أكثر من 45 منت…").
4. **Framing.** Store pages convert better with a headline above the screen. That is design work:
   framed screenshots and the Play feature graphic (brand navy `#0F2144`, orange `#F26522`, the
   logo) come from Figma, using these captures as the source.
5. **Re-capture on every release that changes the UI.**

So: the client puts real, well-photographed products, stores, bundles and hero banners in the store
(Arabic names included), someone points the three constants at good examples, and both platforms are
captured again.
