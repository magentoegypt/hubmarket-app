# Decision — Checkout addresses: reference, don't copy

**Status:** fixed and verified on device, 2026-08-20 · commit `2f10ca6` (1.0.0+85)

## The bug

For a logged-in customer, selecting an **existing** saved address at checkout added
a duplicate copy of that address to their address book on every order. The QA
account had accumulated eight identical entries, one per checkout.

Reported by the owner; reproduced from the address book itself.

## Mechanism

The screen flattened the chosen `CustomerAddress` into a full `CartAddressInput`
and sent it as `shipping_addresses: [{ address: {...} }]`, never using
`customer_address_id`. Magento's `SetShippingAddressesOnCart` then does:

```php
$customerAddressId = $shippingAddressInput['customer_address_id'] ?? null;

if (!$customerAddressId
    && isset($shippingAddressInput['address'])
    && !isset($shippingAddressInput['address']['save_in_address_book'])
) {
    $shippingAddressInput['address']['save_in_address_book'] = true;
}
```

With neither key present it forces the flag **true**, and the flagged quote
address is copied into the address book when the order is placed — which is why
the duplicate appears *after* place-order, not at address submission.
`CartAddressInput.save_in_address_book` is documented the same way: *"The default
value is true."*

**Billing does not compound it.** The app sends `same_as_shipping: true`, which
takes `createBasedOnShippingAddress` and never reaches that branch. One duplicate
per order, not two.

## The fix

Reference the address instead of copying it. `CheckoutQueries.setShippingAddress`
now takes a whole `ShippingAddressInput`, so:

| path | sent | Magento behaviour |
|---|---|---|
| saved address | `{customer_address_id: id}` | `createBasedOnCustomerAddress` — saves nothing, uses the stored address verbatim |
| newly typed address | `{address: {...}}` | saved to the address book, once |

The new-address behaviour is deliberate and was preserved: a shopper who types an
address at checkout expects it kept. Only the already-saved path had to stop
re-saving.

The two shapes are built by `ShippingAddressInput.saved` / `.fresh`
(`lib/features/checkout/domain/shipping_address_input.dart`) rather than inline in
the screen, so the distinction is unit-testable — the guard asserts a saved
address carries no `address` literal and none of the fields Magento would need to
create one. `CheckoutController.submitAddress` takes `lastname` and `telephone`
explicitly, because the id-only input no longer carries them and guest-OTP
tracking reads the phone.

## Device verification (2026-08-20, Xiaomi 24116RNC1I, Android 16, prod release)

Logged-in customer, real orders on the live store, COD. Counts taken after a
force-stop and relaunch, so they are server state and not the app's cache.

| path | order | addresses before → after | result |
|---|---|---|---|
| saved address (Dubai) | `#2000000083`, AED 27 | 2 → **2** | no duplicate |
| new address (Sharjah) | `#2000000084`, AED 32 | 2 → **3** | saved once, as intended |

Two independent signals confirmed the new address was genuinely in effect rather
than silently falling back to the default: delivery moved from AED 10 (Dubai) to
AED 15 (Sharjah table rate), and the confirmation screen read "within 48 hours ·
Sharjah" instead of Dubai's 24 hours.

An earlier attempt (`#2000000082`) was inconclusive — the address book was cleaned
between the baseline count and the check, so the retest above was run against a
freshly confirmed baseline of 2.

Worth recording: the **first APK built for this test silently shipped the old
mutation**. The AOT blob still contained `$address: CartAddressInput!`, so
installing it would have "verified" the fix against unchanged code. `flutter
clean` + rebuild produced a binary carrying `customer_address_id` and
`ShippingAddressInput`, with `CartAddressInput` gone. Always grep `libapp.so` for
a string unique to the change before trusting a device result.

## Open — historical duplicates on live accounts

This fix stops new duplicates. It does **not** clean up rows the bug already
created.

Introduced in `88da563` (2026-07-08), first released in `0.1.65+66`
(2026-07-11) — roughly six weeks live. Exposure is narrower than that window
suggests:

- logged-in customers only (guests have no address book);
- only when picking a saved address, so duplication starts from a customer's
  *second* order onward;
- one duplicate per order.

How many real customers that touches depends on store-release state during the
window, which is not recorded here. **Unmeasured** — the repo has no DB access
(`app/etc/env.php` is absent from the Magento source copy) and the storefront
GraphQL `customer` query is scoped to a single bearer token, so customers cannot
be enumerated from the app side.

To quantify, from a read-only DB session:

```sql
SELECT COUNT(*) AS affected_customers, SUM(dupes) AS total_duplicate_rows
FROM (
  SELECT parent_id,
         COUNT(*) - COUNT(DISTINCT CONCAT_WS('|', firstname, lastname, telephone,
                                             street, city, region_id)) AS dupes
  FROM customer_address_entity
  GROUP BY parent_id
  HAVING dupes > 0
) t;
```

Any cleanup must keep the row referenced by `default_shipping` / `default_billing`
on `customer_entity` — deleting an address that is a default breaks those
pointers.
