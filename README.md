# Hub Market — customer app

The **Hub Market** customer app for Android and iOS, built with **Flutter**: a
headless client for the multi-vendor marketplace at
[hub-market.magento2.click](https://hub-market.magento2.click) (Magento Open
Source 2.4.8-p5 + the Vnecoms marketplace). UAE market, **English (LTR) and
Arabic (RTL)**, prices in **AED**. The app talks to Magento over GraphQL (plus
the WhatsApp-code REST pair for sign-in); it contains no Magento code.

- **Design:** Figma file `rJVCVQdnC59gNbLAWQBZw3` (v3).
- **Rules of the codebase:** [`CLAUDE.md`](CLAUDE.md) — backend facts, tooling,
  what is managed in Magento, brand tokens and conventions.
- **History:** the app started from the Zoonze storefront app; what is left of
  its documentation is in [`docs/zoonze-reference/`](docs/zoonze-reference/),
  as reference only.

## Requirements

- Flutter **3.44.x** (stable) · Dart **3.12.x**
- Python 3 for the GraphQL tooling in `tool/`

## Setup

```bash
flutter pub get
flutter gen-l10n                                      # lib/l10n/app_localizations*.dart
dart run build_runner build --delete-conflicting-outputs   # typed GraphQL (graphql_codegen)
```

## Run

Each flavor reads its settings (GraphQL endpoint, store codes, Algolia…)
from `config/<flavor>.json`. The User-Agent carries the installed build's
version (pubspec `version:`), read at startup:

```bash
flutter run -t lib/main_dev.dart     --dart-define-from-file=config/dev.json     --flavor dev
flutter run -t lib/main_staging.dart --dart-define-from-file=config/staging.json --flavor staging
flutter run -t lib/main_prod.dart    --dart-define-from-file=config/prod.json    --flavor prod
```

Android flavors install side by side (`com.hubmarket.app`, `.dev`, `.staging`).

## Check before pushing

```bash
flutter analyze
flutter test
PYTHONIOENCODING=utf-8 python tool/validate_ops.py   # every GraphQL document vs the live schema + the HubApp contract — must report 0 problems
python -m unittest discover -s tool -p "test_*.py"   # the tooling's own tests
```

`python tool/introspect_to_sdl.py` refreshes `lib/core/graphql/schema.graphql`
from the live endpoint; CI checks the operations against that committed copy
(`validate_ops.py --schema-file lib/core/graphql/schema.graphql`). Tooling and
tests only ever **query** the live server (and introspect it); they never send
a mutation.

Some widget tests also render screens in English and Arabic, with the bundled
fonts, to `build/test_screens/*.png` for comparison with the Figma frames.

## Project layout

```
lib/
  app/        MaterialApp.router, routes, theme (Figma tokens, fonts, text styles), shell
  core/       config · graphql (link chain, resilience) · hubapp (Hub Market App API
              probe, settings) · store views · storage · error · network (connectivity)
              · validation · widgets
  features/   auth · catalog (search, PLP, PDP, reviews) · home · cart · checkout
              · account · wishlist · cms · notifications · onboarding · diagnostics
              · app_status · deals · marketplace · returns · store_credit · stores
              (each data / domain / presentation)
  l10n/       app_en.arb · app_ar.arb
assets/       branding (logo, app icon) · fonts (DM Sans, Tajawal, Playfair Display + OFL)
config/       dev · staging · prod
tool/         introspect_to_sdl.py · validate_ops.py · CI / iOS helper scripts
.github/      ci · build-on-push · release-android · release-ios · build-ios · iOS screenshot / deep-link checks
```

## Fonts

DM Sans (Latin) and Tajawal (Arabic) set the UI text, Playfair Display the
English display headings — the Figma "01 · Cover & Foundations" styles. All
three are SIL Open Font License fonts from google/fonts; their licences ship in
`assets/fonts/licenses/` and appear on the app's licences page.
