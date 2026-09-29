# Payment brand marks

Drop the **official** wallet marks here as PNG:

| file | source |
|---|---|
| `apple_pay_mark.png` (+ `@2x`, `@3x`) | Apple Pay Marketing Guidelines → "Apple Pay Mark" artwork |
| `apple_pay_mark_white.png` (+ `@2x`, `@3x`) | the white variant, for dark mode |
| `samsung_pay_mark.png` (+ `@2x`, `@3x`) | Samsung Pay / Samsung Wallet brand assets |
| `samsung_pay_mark_white.png` (+ `@2x`, `@3x`) | the white variant, for dark mode |

Height in the checkout row is 20 logical px; supply 1x/2x/3x accordingly.

These exact filenames are what `PaymentMethodCard._methodMark` loads. Renaming
either side is silent: `errorBuilder` cannot tell a wrong name from a missing
file, so both just fall back to the Material icon.

**Do not substitute a font glyph or a redrawn logo.** Apple's guidelines forbid
recreating or recolouring the Apple Pay mark, and doing so on a payment screen is
a plausible App Review flag. Until the licensed artwork is present,
`PaymentMethodCard._methodMark` falls back to a neutral Material wallet icon —
that fallback is the intended interim state, not a bug.
