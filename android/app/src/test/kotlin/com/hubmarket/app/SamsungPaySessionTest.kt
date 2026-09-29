package com.hubmarket.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Covers the two pure helpers in [SamsungPaySession] — no device, no Samsung SDK
 * setup, no N-Genius outlet. Everything else in that class is callbacks around
 * the SDK and belongs to the device QA pass.
 */
class SamsungPaySessionTest {

    // ---- mapFailure ---------------------------------------------------------

    @Test
    fun `user cancelled maps to CANCELLED`() {
        // The exact string SamsungPayTransactionListener builds for SpaySdk
        // ERROR_USER_CANCELED. Cancelled must not read as a failure: the
        // complete-payment screen shows different copy for the two.
        val (status, raw) = SamsungPaySession.mapFailure(
            "Samsung Pay authorization failed with code -7 (User canceled)",
        )
        assertEquals("CANCELLED", status)
        assertEquals("samsungpay: Samsung Pay authorization failed with code -7 (User canceled)", raw)
    }

    @Test
    fun `network error maps to FAILED and keeps the reason`() {
        val (status, raw) = SamsungPaySession.mapFailure(
            "Samsung Pay authorization failed with code -21",
        )
        assertEquals("FAILED", status)
        assertNotNull(raw)
        assertEquals(true, raw!!.contains("-21"))
    }

    @Test
    fun `outlet not enabled maps to FAILED`() {
        // The SDK's own string when _links has no payment:samsung_pay. No numeric
        // code, so it must fall through to FAILED rather than being mis-parsed.
        val (status, _) = SamsungPaySession.mapFailure("Samsung Pay is not enabled")
        assertEquals("FAILED", status)
    }

    @Test
    fun `decryption failure maps to FAILED, never success`() {
        // The customer authenticated and Samsung produced a token, but N-Genius
        // rejected it. The order may or may not be authorised server-side, so the
        // app must route to the retry screen and re-query Magento.
        val (status, _) = SamsungPaySession.mapFailure("Samsung Pay decryption failed")
        assertEquals("FAILED", status)
    }

    @Test
    fun `null message maps to FAILED with no raw`() {
        val (status, raw) = SamsungPaySession.mapFailure(null)
        assertEquals("FAILED", status)
        assertNull(raw)
    }

    // ---- buildOrder ---------------------------------------------------------

    private val orderJson = """
        {
          "reference": "ord_abc123",
          "outletId": "outlet_xyz",
          "amount": { "currencyCode": "AED", "value": 19900 },
          "paymentMethods": { "card": ["VISA", "MASTERCARD"] },
          "_links": {
            "payment": { "href": "https://paypage.ngenius.test/?code=abc" },
            "payment-authorization": { "href": "https://api.ngenius.test/authorize" }
          },
          "_embedded": {
            "payment": [
              {
                "outletId": "outlet_xyz",
                "_links": {
                  "payment:samsung_pay": { "href": "https://api.ngenius.test/samsung" },
                  "payment:card": { "href": "https://api.ngenius.test/card" }
                }
              }
            ]
          }
        }
    """.trimIndent()

    @Test
    fun `buildOrder reads every field the SDK consumes`() {
        val order = SamsungPaySession.buildOrder(orderJson)
        assertNotNull(order)
        requireNotNull(order)

        assertEquals("ord_abc123", order.reference)
        assertEquals("outlet_xyz", order.outletId)
        assertEquals("AED", order.amount?.currencyCode)
        assertEquals(19900.0, order.amount?.value!!, 0.0001)
        assertEquals(listOf("VISA", "MASTERCARD"), order.paymentMethods?.card)

        // These two are NOT interchangeable — payment-authorization is the API the
        // SDK authorizes against, payment is the hosted pay page carrying ?code=.
        assertEquals(
            "https://api.ngenius.test/authorize",
            order.links?.paymentAuthorizationUrl?.href,
        )
        assertEquals(
            "https://paypage.ngenius.test/?code=abc",
            order.links?.paymentUrl?.href,
        )

        // The outlet-enablement gate.
        assertEquals(
            "https://api.ngenius.test/samsung",
            order.embedded?.payment?.firstOrNull()?.links?.samsungPayLink?.href,
        )
    }

    @Test
    fun `buildOrder returns null for absent or malformed json`() {
        assertNull(SamsungPaySession.buildOrder(null))
        assertNull(SamsungPaySession.buildOrder(""))
        assertNull(SamsungPaySession.buildOrder("not json at all"))
    }

    @Test
    fun `buildOrder leaves the samsung link null when the outlet lacks it`() {
        // This is what an outlet without Samsung Pay enabled looks like, and it is
        // the case SamsungPaySession.start pre-flights so the reported reason names
        // outlet configuration rather than the device.
        val withoutSamsung = orderJson.replace(
            "\"payment:samsung_pay\": { \"href\": \"https://api.ngenius.test/samsung\" },",
            "",
        )
        val order = SamsungPaySession.buildOrder(withoutSamsung)
        assertNotNull(order)
        assertNull(order!!.embedded?.payment?.firstOrNull()?.links?.samsungPayLink)
    }
}
