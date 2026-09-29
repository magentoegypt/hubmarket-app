# N-Genius: card payments fail through GraphQL, work on the website

**Status:** root cause confirmed 2026-07-29. Fix is backend-only — nothing to
change in the Flutter app.

**Symptom:** in the app, choosing "Visa / Master cards" places the order but no
card screen ever appears. The same method works on the website.

---

## What the app sees

Captured on-device via the payment trace (Settings → Connection test → Payment
trace), order `2000000052`:

```
run: session FAILED
session: 2000000052 ngenius/ngeniusonline status=failed webUrl=false (auth=customer/bearer)
```

So `paymentSession` **found the order** and answered correctly — it reported a
session that had already failed server-side, with no `web_url`. Per
`payment-contract.md`, `FAILED` is "our-side error creating the session", and
the app is right not to launch the SDK for it.

The client side is not implicated: the query matches the deployed schema, and
the N-Genius SDK is present in both binaries (`NISdk.framework` in the IPA,
`payment/sdk/android` in `classes.dex`).

---

## Root cause

`NetworkInternational\NGenius\Gateway\Http\Client\PaymentTransaction::postProcess()`
(vendor module **1.1.7**) writes the `ngenius_networkinternational_sales_order`
row that `paymentSession` later reads. It builds that row **entirely from the
checkout session**:

```php
$data = $this->checkoutSession->getData();      // Magento\Checkout\Model\Session
...
$data['order_id']  = $data['last_real_order_id'];
$data['entity_id'] = $data['last_order_id'];
$model = $this->coreFactory->create();
$model->addData($data);
$model->save();
```

**GraphQL is stateless — there is no checkout session.** Through the web
checkout, `last_real_order_id` and `last_order_id` are populated and the row
links to the order. Through GraphQL `placeOrder` both are absent, so the row is
saved without a usable `order_id`, and the resolver finds no gateway order for
that increment id → `FAILED`.

This is a vendor-module limitation: N-Genius 1.1.7 assumes web checkout and is
not GraphQL-aware. It is not a misconfiguration — the credentials, outlet
reference and environment are all correct, which is why the website works.

---

## Fix

The gateway request already carries the Magento order id:

```php
// Gateway/Request/PaymentRequest.php:144
'merchantOrderReference' => $order->getRealOrderId(),
```

So the order can be recovered without the session. Rather than override
`postProcess()` (protected, and duplicating vendor logic), populate the session
keys it expects **before** the vendor code runs, in a plugin on the public
`placeRequest()`. The vendor module then works unchanged, on both channels.

Add to `MagentoEgypt_PaymentGraphQl` (or a small dedicated module):

```xml
<!-- etc/di.xml -->
<type name="NetworkInternational\NGenius\Gateway\Http\Client\PaymentTransaction">
    <plugin name="magentoegypt_ngenius_graphql_session"
            type="MagentoEgypt\PaymentGraphQl\Plugin\NGeniusCheckoutSessionPlugin"/>
</type>
```

```php
<?php
namespace MagentoEgypt\PaymentGraphQl\Plugin;

use Magento\Checkout\Model\Session as CheckoutSession;
use Magento\Payment\Gateway\Http\TransferInterface;
use Magento\Sales\Model\OrderFactory;
use NetworkInternational\NGenius\Gateway\Http\Client\PaymentTransaction;

/**
 * N-Genius 1.1.7 stores its gateway order using last_real_order_id /
 * last_order_id from the checkout session. GraphQL has no checkout session, so
 * the row is written without an order link and paymentSession later reports
 * FAILED. The order id is already in the request as merchantOrderReference —
 * seed the session from it so the vendor code works on both channels.
 */
class NGeniusCheckoutSessionPlugin
{
    public function __construct(
        private readonly CheckoutSession $checkoutSession,
        private readonly OrderFactory $orderFactory
    ) {
    }

    public function beforePlaceRequest(
        PaymentTransaction $subject,
        TransferInterface $transferObject
    ): void {
        // Web checkout already has these; only fill in when they're missing.
        if ($this->checkoutSession->getLastRealOrderId()) {
            return;
        }

        $body = $transferObject->getBody();
        $incrementId = is_array($body) ? ($body['merchantOrderReference'] ?? null) : null;
        if (!$incrementId) {
            return;
        }

        $order = $this->orderFactory->create()->loadByIncrementId($incrementId);
        if (!$order->getId()) {
            return;
        }

        $this->checkoutSession->setLastRealOrderId($order->getIncrementId());
        $this->checkoutSession->setLastOrderId($order->getId());
    }
}
```

### Verifying the fix

1. Place an order through the app with `ngeniusonline`.
2. `SELECT order_id, entity_id, reference, state FROM ngenius_networkinternational_sales_order ORDER BY id DESC LIMIT 1;`
   — `order_id` must be the increment id and `state` `PENDING_AUTHORIZATION`.
3. The app's payment trace should then read
   `status=ready webUrl=true`, and the card screen should open.

### Backfill

Orders already placed through the app (2000000047, 2000000052, …) have no
usable gateway row and cannot be paid from the app. They need cancelling, or
paying through the website.

---

## Not the cause, but worth fixing

`checkout_controller.dart:147` treats a token left in secure storage as
authoritative over the customer's choice:

```dart
final guest = isGuest && !hasToken;
```

Order 2000000047 was placed as a **registered customer** despite guest checkout
being selected, which is why Magento's `guestOrder` lookup could not find it
during diagnosis. Silently ordering under a previously signed-in account is
surprising; the token should either be cleared or the customer told they're
signed in.
