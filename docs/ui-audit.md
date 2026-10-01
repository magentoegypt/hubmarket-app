# UI audit: the app against the Figma frames

Goal: every screen of the app looks like its frame in Figma `rJVCVQdnC59gNbLAWQBZw3` (v3, the
approved design) and has every element the frame has, unless the backend cannot provide it or the
team decided otherwise (see "Deliberate deviations"). This file is the working guide: how to compare,
the shared pieces to build with, and the rules.

## 0. First thing in a fresh worktree

```
bash tool/ui_audit/setup_worktree.sh     # pub get, l10n, GraphQL codegen, copies the Figma frames
```

## 1. How to compare a screen

1. **The frame.** Figma MCP tools (`mcp__bb8fb8e6-fa3b-4285-8dfe-4f5401d19390__*`, load them with
   ToolSearch if they are deferred):
   - `get_screenshot(fileKey, nodeId)` returns a short-lived URL; download it with PowerShell
     `Invoke-WebRequest -Uri <url> -OutFile <png>` (Git Bash `curl` fails with error 43). Frames are 390 wide
     and include a 47 px status bar on top and a 34 px home-indicator zone at the bottom; tall frames
     show the whole scroll. The 59 English frames are already downloaded to
     `build/ui_audit/figma/<name>.png` (copied by the setup script; names in `tool/ui_audit/pairs.py`). The Arabic
     frames are not: download the ones you need to `build/ui_audit/figma_ar/<same name>.png` (ids in section 5),
     then `python tool/ui_audit/pairs.py ar <filter>` composes them against the `_ar` renders.
   - `get_design_context(fileKey, nodeId, skillNames: "figma-design-to-code", clientFrameworks: "flutter",
     clientLanguages: "dart")` returns React/Tailwind reference code with the exact px, colours, fonts and
     the layout of the frame. Convert it to Flutter by hand (do not copy Tailwind classes); it also names
     the Figma text styles (`EN/Body`, `AR/Caption`, ...), which are `AppTextStyles` in code.
   - `get_metadata(fileKey, nodeId)` returns every child's x / y / width / height: use it for spacing.
   - Arabic frames: the same file, canvas "AR" next to the EN canvas; read them when you check RTL.
2. **The app.** Write (or reuse) a widget test that renders the screen with fakes and calls
   `captureScreen(tester, key, 'audit_<name>_<locale>')` from `test/support/fonts.dart`; it writes
   `build/test_screens/<name>.png` at 1x. Run it with the safe-area insets of an iPhone (47 top, 34 bottom)
   so the frame and the render line up:

   ```
   flutter test --dart-define=UI_AUDIT=true test/path/to/capture_test.dart
   ```

   Look at `test/features/account/p1_screens_render_test.dart` and `test/features/onboarding/welcome_screen_test.dart`
   for the harness (390 x 844, DPR 1, `loadAppFonts()` in `setUpAll`, a `RepaintBoundary` key). Images from the
   network are not available in tests (placeholder tint), and emoji and Arabic fall back to boxes in some
   test fonts: those are test artefacts, not bugs.
3. **Side by side.** `python tool/ui_audit/compose.py FIGMA.png APP.png OUT.png` puts the frame on the left and
   the render on the right (chunks of 844 px). `python tool/ui_audit/pairs.py en <filter>` does it for every
   mapped pair into `build/ui_audit/cmp/`. Read the composite with the Read tool (it shows the image).
4. Work through the differences top to bottom: layout and spacing, type (size, weight, colour, line height),
   colours, radii, borders, icons, missing and extra elements, states (empty, loading, error) the frame draws.
   Fix, re-render, compare again. Then do the Arabic frame the same way for the screens you touched.

## 2. Shared pieces (use them, do not rebuild them)

| Piece | Where | Figma |
|---|---|---|
| Colours | `lib/app/theme/app_colors.dart` | Color tokens 26:179 |
| Text styles `AppTextStyles.of(context)`: `display`, `heading1`, `heading2`, `title`, `body`, `bodyStrong`, `caption`, `captionStrong`, `micro`, `button`, `price`, `priceLarge` | `lib/app/theme/app_text_styles.dart` | Type ramp 26:354 |
| Icons `HubIcons.*` (Lucide, 24 px, stroke 2: the Figma icon set) | `lib/app/theme/hub_icons.dart`, font `assets/fonts/Lucide.ttf` | Icons 4:2 |
| Product card, `ProductGridDelegate` / `productGridDelegate(context)`, `ProductCardMetrics` | `lib/features/catalog/presentation/widgets/product_card.dart` | Product card 6:188 |
| Bottom tab bar | `lib/app/shell/hub_bottom_nav.dart` | Tab bar 5:369 |
| Filled / outlined buttons (theme), `HubButton` variants | `lib/app/theme/app_theme.dart`, `lib/core/widgets/hub_button.dart` | Button 5:400 |
| Fields: `AuthField` (label over a white 52 px field), the global `InputDecorationTheme` | `lib/features/auth/presentation/widgets/auth_field.dart` | Input 6:247 |
| Chips `HubChip` | `lib/core/widgets/hub_chip.dart` | Chip 6:321 |
| App bar `HubTopBar`, `HubIconButton`, `HubBackButton`; `subpageAppBar` | `lib/core/widgets/` | App bar inside each frame |
| Section header `HmSectionHeader` | `lib/features/home/presentation/widgets/hm_section_header.dart` | section-header/... |
| Grouped lists `GroupCard`, `GroupLabel` | `lib/core/widgets/grouped_list.dart` | Account frames |

Icons are Lucide outlines. Where the frame shows a **filled** heart or star, use the Material glyph
(`Icons.favorite`, `Icons.star_rounded`). Arrows and chevrons in `HubIcons` mirror in RTL by themselves:
never flip them by hand.

Prices: `Money.formatted()` drops the decimals of a whole amount ("AED 425"), as the frames do, and keeps
them otherwise ("AED 12.50").

## 3. Rules

- **No made-up data.** A section the backend cannot fill stays hidden (see CLAUDE.md section 3 and the
  deliberate deviations below). Never invent a rating, a store, a coupon or a banner to match a frame.
- **Directional layout** everywhere: `EdgeInsetsDirectional`, `AlignmentDirectional`, `PositionedDirectional`.
- Every visible string is localised (`lib/l10n/app_en.arb` / `app_ar.arb`; run `flutter gen-l10n` or any
  `flutter test` after editing). When you add keys, insert them next to related existing keys, not at the end
  of the file, so branches merge cleanly.
- Keep the behaviour: this audit changes how screens look, not what they do. Existing tests that assert a
  behaviour must still pass; change a test only when it asserts a widget that the design replaced (an icon,
  a button label that the frame words differently), and say so in your summary.
- Never send a GraphQL mutation to the live server from tooling or tests.
- `flutter analyze` must report no issues and `flutter test` must pass before you hand back.
- Do not push, do not touch the CI files, the pubspec dependencies or the release docs.
- Small, focused commits on your branch; the commit message ends with the Co-Authored-By trailer.

## 4. Deliberate deviations (leave them, do not fix them toward the frame)

- No social sign-in (Apple / Google / Facebook) and no per-store coupons or per-store delivery estimates:
  the backend has none.
- "AI ENGINE" badge and personalisation claims on "Picked for you" are removed (QA02).
- No free-shipping progress bar: the live schema has no threshold (`free_shipping_subtotal`).
- Password rule and OTP masking copy follow the product decision, not the frame.
- Tabby / Tamara blocks: the live backend has no `tabbyConfig` and no Tamara session.
- Anything the HubApp contract (`lib/core/graphql/hubapp.graphql`) cannot provide is hidden, not faked.
- Test artefacts that are not bugs: tofu boxes for emoji and Arabic in test renders, missing network images,
  zero insets when `UI_AUDIT` is off.

## 5. Frame map (English canvas 2:3, 390 x 844 unless noted)

A Onboarding and auth: 01 Splash 11:2 · 01a Launch 113:4133 · 02 Welcome 11:31 · 03 Sign in 11:78 ·
04 Register 12:74 · 05 Verify 12:173 · 06 Forgot 12:229 ·
B Discovery: 07 Home 33:1669 (390 x 6313) · 08 Categories 13:468 · 09 Search 14:436 · 09b Search landing 59:2305 ·
09c Search results 59:2473 · 10 PLP 14:541 · 10b Deals 84:3074 · 10c Bundles 83:2898 · 10d Brands 93:3658 ·
10e Brand page 93:3781 · 11 Filters 14:759 (963) ·
C Stores and product: 12 Stores 15:676 · 13 Store 15:873 · 13b Store about 83:3056 (1075) · 14 PDP 16:970 (2379) ·
14b Bundle PDP 61:2674 (1156) · 14c Added to cart 91:3768 · 15 Reviews 16:1118 · 15b Write review 83:3194 (1110) ·
D Cart and checkout: 16 Cart 62:2639 (1310) · 17 Shipping 62:2837 · 17a Guest 63:2649 (1079) · 18 Payment 19:1180 (1038) ·
18b Review 63:2785 (1117) · 19 Order placed 19:1294 ·
E Account: 20 Account 66:2845 (1287) · 20b Privacy 66:3046 · 20c Profile 84:3256 (1124) · 20d Credit 89:3516 (761) ·
20e Payment methods 89:3603 · 20f My reviews 89:3659 · 20g Notifications 91:3592 · 20h Notification settings 91:3686 ·
21 Orders 20:1401 · 21b Cancel order 64:2779 · 22 Order detail 21:1376 (1562) · 23 Return request 65:2759 (1086) ·
23b My returns 65:2876 · 23c Return detail 65:2981 · 24 Addresses 22:1452 · 24b Address form 84:3411 (1198) ·
25 Wishlist 22:1513 · 26 Track order 85:3365 · 27 Help 85:3462 (1460) · 28 CMS page 85:3629 ·
F States: S1 Empty cart 23:5 · S2 No results 23:87 · S3 Offline 23:133 · S4 Loading 23:216 · S5 Payment failed 23:314 ·
S6 Sign-in errors 23:360 · S7 Not found 94:4109.
Arabic (RTL) canvas 2:4, the same screens, frame ids: AR-01 46:1273 · AR-01a 113:8269 · AR-02 46:1299 ·
AR-03 46:1345 · AR-04 47:1345 · AR-05 47:1443 · AR-06 47:1499 · AR-07 Home 40:572 (390 x 6427) · AR-08 48:1442 ·
AR-09 48:1568 · AR-09b 67:2495 · AR-09c 67:2663 · AR-10 49:1539 · AR-10b 95:3092 · AR-10c 95:3274 · AR-10d 95:3432 ·
AR-10e 95:3557 · AR-11 49:1757 (981) · AR-12 50:1745 · AR-13 24:247 · AR-13b 96:3475 (1073) · AR-14 56:2527 (2479) ·
AR-14b 68:2864 (1180) · AR-14c 96:3613 · AR-15 50:1923 · AR-15b 96:3683 (1112) · AR-16 69:2829 (1334) · AR-17 69:3025 ·
AR-17a 70:2842 (1101) · AR-18 25:504 (1048) · AR-18b 70:2978 (1147) · AR-19 51:2024 · AR-20 74:3038 (1331) ·
AR-20b 74:3239 · AR-20c 97:3593 (1146) · AR-20d 97:3749 (793) · AR-20e 97:3834 · AR-20f 98:3722 · AR-20g 98:3810 ·
AR-20h 98:3904 · AR-21 52:1961 · AR-21b 71:2972 · AR-22 52:2104 (1600) · AR-23 72:2956 (1106) · AR-23b 72:3073 ·
AR-23c 72:3178 · AR-24 53:2139 · AR-24b 99:3799 (1208) · AR-25 53:2200 · AR-26 99:3944 · AR-27 99:4045 (1486) ·
AR-28 99:4212 · AR-S1 54:2287 · AR-S2 54:2354 · AR-S3 54:2399 · AR-S4 54:2468 · AR-S5 54:2554 · AR-S6 54:2600 ·
AR-S7 101:4180.
Backend-managed content map (what the admin edits): G1 192:4451, admin screens G2a 198:5360 / G2b 199:5362.
Components (page 2:2): Status bar 5:28 · Tab bar 5:369 · Button 5:400 · Product card 6:188 · Input 6:247 ·
Store card 6:298 · Store tile 6:299 · Chip 6:321 · Color tokens 26:179 · Type ramp 26:354 · Top vendor card 39:235 ·
Icons 4:2.
