# Device audit: every Figma screen on the phone

`docs/ui-audit.md` compares each frame with a render in the test renderer at 390 x 844. This audit does
the same on a **real phone**, which is 360 dp wide (30 dp narrower than the frames), has a real status bar
and navigation bar, and draws with the real GPU and fonts. It also runs the whole app UI **without logging
in, without the network and without sending anything to the server**: every screen is the real widget with
the fakes of the widget tests.

Three pieces, all in this repo:

| Piece | What it is |
|---|---|
| `integration_test/device_audit/` | The **scenes**: one `AuditScene` per frame state (`scenes_<group>.dart`), the runner (`harness.dart`) and the registry (`scenes.dart`). |
| `test/device_audit/device_audit_host_test.dart` | The **host sweep**: every scene in the test renderer at the phone's size and insets (720 x 1640 px, 2x, a 34 dp status bar, a 47 dp navigation bar). Fast, no phone. Fails on a layout overflow or any other framework error. Captures go to `build/device_audit_host/`. |
| `integration_test/device_audit_test.dart` | The **phone run**: the same scenes, captured with `takeScreenshot` into `build/device_audit/` (`tool/device_audit.sh`). |

## Run it

```
flutter test test/device_audit/device_audit_host_test.dart                          # every scene, en + ar
flutter test test/device_audit/device_audit_host_test.dart --dart-define=AUDIT_ONLY=E21     # ids containing E21
```

Captures are named `<locale>-<frame>__<state>[__s<n>].png`, for example `en-E21_orders__default.png`;
`__s1`, `__s2` ... are the screen scrolled down by about a screen each (a tall frame shows the whole scroll,
the phone one screen at a time).

On the phone (the Android phone's OS asks for a tap on **Install** each time, so someone must hold it):

```
bash tool/device_audit.sh                    # en + ar
AUDIT_ONLY=E21,E22 bash tool/device_audit.sh
python tool/ui_audit/device_pairs.py en      # the frame on the left, the phone on the right
```

## Write a scene

A scene is the widget test that already renders the frame, made reusable. `PAIRS` in
`tool/ui_audit/pairs.py` says which capture shows which frame (`'E21_orders': ['audit_21_orders']`); find the
test with `rg "audit_21_orders" test` and port it:

```dart
AuditScene(
  frame: 'E21_orders',            // the PAIRS key
  name: 'default',                // one scene per frame state: default, empty, sheet ...
  screen: (locale) => const OrdersScreen(),
  setup: (locale) => AuditSetup(  // the fakes the test passes to pumpAudit
    account: FakeAccountRepository(orders: _orders(locale)),
    returns: FakeReturnsRepository(),
    overrides: [/* any other provider */],
  ),
  act: (tester, locale) async {   // taps that open a sheet, a typed field, a tab ...
    await tester.tap(find.text('Cancel order'));
    await pumpFor(tester, 500);
  },
  scrolls: 2,                     // extra captures, scrolled down by a screen each
)
```

- **Copy the fixtures** (the private `_orders(locale)` helpers) into the scene file; do not edit the existing
  tests. Fixtures that depend on the locale do what the test does (`ar ? '...' : '...'`).
- The harness mounts the screen like `pumpAudit` does (`test/support/audit_pump.dart`: `auditRouter`,
  `auditOverrides`, `auditApp`): at `/screen` on top of Home, every tab route a stub, signed in unless
  `signedIn: false`, `pushed: false` for a tab root. A screen that reads a provider the harness does not fake
  needs it in `overrides`.
- Use `pumpFor(tester, ms)`, not `pumpAndSettle` (the skeletons and carousels never go quiet).
- `scrolls`: a tall frame (heights in `docs/ui-audit.md` section 5) is one phone screen of about 740 dp per
  capture; `scrolls: ceil((frameHeight - 844) / 630)`, at most 4.
- **Never** send a GraphQL mutation, call the network or read a secret: fakes only. Images in fixtures may
  be real catalogue URLs (they load on the phone) or none.
- A scene must pass the host sweep in English and Arabic. A **layout overflow at 360 dp is a finding, not a
  scene bug**: do not silence it, do not widen the test surface; report the frame, the widget and the
  overflow in pixels.

## Compare

`device_pairs.py` puts the frame (390 wide) beside the phone capture at 1 dp = 1 px (360 wide) and writes
`build/device_audit/cmp/`. What to look for that the 390 dp audit could not show: text that wraps or clips
at 360, rows that no longer fit, chips and buttons cut at the edge, content under the status bar or the
navigation bar, the tab bar's height with the Android bars, the real fonts, shadows and icons, and the
yellow-and-black overflow stripes Flutter paints in a debug build.
